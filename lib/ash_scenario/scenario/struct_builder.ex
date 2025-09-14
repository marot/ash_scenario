defmodule AshScenario.Scenario.StructBuilder do
  @moduledoc """
  Builds structs from prototypes without database persistence.
  Used for generating test data for stories and other non-persistent use cases.
  """

  alias AshScenario.Scenario.{Registry, Helpers}
  alias AshScenario.Log

  @doc """
  Build a single prototype as a struct without persistence.
  """
  def run_prototype_structs(resource_module, prototype_name, opts \\ []) do
    case run_prototypes_structs([{resource_module, prototype_name}], opts) do
      {:ok, created} -> {:ok, created[{resource_module, prototype_name}]}
      error -> error
    end
  end

  @doc """
  Build multiple prototypes as structs with dependency resolution.
  """
  def run_prototypes_structs(prototype_refs, opts \\ []) when is_list(prototype_refs) do
    {opts, trace} = Log.ensure_trace(opts)
    started_at = System.monotonic_time(:millisecond)

    {normalized_refs, overrides_map} = Helpers.normalize_refs_and_overrides(prototype_refs, opts)

    debug_refs = Enum.map(normalized_refs, fn {m, r} -> {m, r} end)

    Log.debug(
      fn ->
        "run_prototypes_structs start refs=#{inspect(debug_refs)} overrides=#{inspect(overrides_map)}"
      end,
      component: :struct_builder,
      trace_id: trace
    )

    with {:ok, ordered_prototypes} <- Registry.resolve_dependencies(normalized_refs) do
      Log.debug(
        fn ->
          "dependency_order=#{Enum.map(ordered_prototypes, &{&1.resource, &1.ref}) |> inspect()}"
        end,
        component: :struct_builder,
        trace_id: trace
      )

      Enum.reduce_while(ordered_prototypes, {:ok, %{}}, fn prototype, {:ok, created_structs} ->
        # Use a custom creator function that builds structs instead of using Ash.create
        creator_fn = &create_struct/3

        case execute_prototype(
               prototype,
               Keyword.put(opts, :__overrides_map__, overrides_map),
               created_structs,
               creator_fn
             ) do
          {:ok, created_struct} ->
            key = {prototype.resource, prototype.ref}
            created_structs = Map.put(created_structs, key, created_struct)

            # Also index by the actual struct module returned, to support custom functions
            struct_mod = created_struct.__struct__

            created_structs =
              if struct_mod != prototype.resource do
                Map.put(created_structs, {struct_mod, prototype.ref}, created_struct)
              else
                created_structs
              end

            {:cont, {:ok, created_structs}}

          {:error, reason} ->
            Log.error(
              fn ->
                "run_prototypes_structs halted module=#{inspect(prototype.resource)} ref=#{prototype.ref} reason=#{inspect(reason)}"
              end,
              component: :struct_builder,
              resource: prototype.resource,
              ref: prototype.ref,
              trace_id: trace
            )

            {:halt, {:error, reason}}
        end
      end)
      |> tap(fn _ ->
        duration = System.monotonic_time(:millisecond) - started_at

        Log.info(fn -> "run_prototypes_structs finished duration_ms=#{duration}" end,
          component: :struct_builder,
          trace_id: trace
        )
      end)
    end
  end

  @doc """
  Build all prototypes defined for a resource module as structs.
  """
  def run_all_prototypes_structs(resource_module, opts \\ []) do
    prototypes = Registry.get_prototypes(resource_module)
    prototype_refs = Enum.map(prototypes, fn r -> {r.resource, r.ref} end)
    run_prototypes_structs(prototype_refs, opts)
  end

  # Shared execution logic with custom creator function
  defp execute_prototype(prototype, opts, created_resources, creator_fn) do
    {opts, trace} = Log.ensure_trace(opts)

    Log.debug(
      fn ->
        "execute_prototype_struct start module=#{inspect(prototype.resource)} ref=#{prototype.ref}"
      end,
      component: :struct_builder,
      resource: prototype.resource,
      ref: prototype.ref,
      trace_id: trace
    )

    overrides_map = Keyword.get(opts, :__overrides_map__, %{})
    per_ref_overrides = Map.get(overrides_map, {prototype.resource, prototype.ref}, %{})

    base_attributes =
      cond do
        is_map(prototype.attributes) -> prototype.attributes
        is_list(prototype.attributes) -> Map.new(prototype.attributes)
        is_nil(prototype.attributes) -> %{}
        true -> %{}
      end

    merged_attributes = Map.merge(base_attributes, per_ref_overrides)

    # Track which keys were explicitly set to nil in overrides
    explicit_nil_keys =
      per_ref_overrides
      |> Enum.filter(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(&elem(&1, 0))

    with {:ok, resolved_attributes} <-
           resolve_struct_attributes(merged_attributes, prototype.resource, created_resources) do
      module_cfg = AshScenario.Info.create(prototype.resource)
      res_fn = Map.get(prototype, :function)
      res_action = Map.get(prototype, :action)

      # Extract tenant info for custom functions
      {:ok, tenant_value, _clean_attributes} =
        AshScenario.Multitenancy.extract_tenant_info(prototype.resource, resolved_attributes)

      # Add tenant to opts for custom functions
      opts_with_tenant = AshScenario.Multitenancy.add_tenant_to_opts(opts, tenant_value)

      cond do
        # Custom functions work the same for both modes
        res_fn != nil ->
          Log.debug(
            fn ->
              "using_custom_function (prototype override) module=#{inspect(prototype.resource)} ref=#{prototype.ref}"
            end,
            component: :struct_builder,
            resource: prototype.resource,
            ref: prototype.ref,
            trace_id: trace
          )

          case Helpers.execute_custom_function(res_fn, resolved_attributes, opts_with_tenant) do
            {:ok, created_resource} ->
              Helpers.track_created_resource(created_resource, prototype)
              {:ok, created_resource}

            {:error, error} ->
              {:error,
               "Failed to create struct #{inspect(prototype.resource)} with custom function: #{inspect(error)}"}
          end

        # Module-level custom function  
        module_cfg.function != nil ->
          Log.debug(
            fn ->
              "using_custom_function (module-level) module=#{inspect(prototype.resource)} ref=#{prototype.ref}"
            end,
            component: :struct_builder,
            resource: prototype.resource,
            ref: prototype.ref,
            trace_id: trace
          )

          case Helpers.execute_custom_function(
                 module_cfg.function,
                 resolved_attributes,
                 opts_with_tenant
               ) do
            {:ok, created_resource} ->
              Helpers.track_created_resource(created_resource, prototype)
              {:ok, created_resource}

            {:error, error} ->
              {:error,
               "Failed to create struct #{inspect(prototype.resource)} with custom function: #{inspect(error)}"}
          end

        # Default creation - use the creator function (struct vs Ash.create)
        true ->
          Log.debug(
            fn ->
              "using_default_struct_creation module=#{inspect(prototype.resource)} ref=#{prototype.ref}"
            end,
            component: :struct_builder,
            resource: prototype.resource,
            ref: prototype.ref,
            trace_id: trace
          )

          _action = res_action || module_cfg.action || :create

          case creator_fn.(
                 prototype.resource,
                 resolved_attributes,
                 Keyword.put(opts_with_tenant, :__explicit_nil_keys__, explicit_nil_keys)
               ) do
            {:ok, created_resource} ->
              Helpers.track_created_resource(created_resource, prototype)
              {:ok, created_resource}

            {:error, error} ->
              {:error,
               "Failed to create struct #{inspect(prototype.resource)}: #{inspect(error)}"}
          end
      end
    end
  end

  # Resolve attributes for struct mode - returns structs instead of IDs for relationships
  defp resolve_struct_attributes(attributes, resource_module, created_structs) do
    Log.debug(
      fn ->
        "resolve_struct_attributes module=#{inspect(resource_module)} attrs=#{inspect(attributes)}"
      end,
      component: :struct_builder,
      resource: resource_module
    )

    resolved =
      attributes
      |> Enum.map(fn {key, value} ->
        {:ok, resolved_value} =
          resolve_struct_attribute_value(value, key, resource_module, created_structs)

        {key, resolved_value}
      end)
      |> Map.new()

    {:ok, resolved}
  end

  # For struct mode, resolve to structs instead of IDs
  defp resolve_struct_attribute_value(value, attr_name, resource_module, created_structs)
       when is_atom(value) do
    if Helpers.is_relationship_attribute?(resource_module, attr_name) do
      case Helpers.related_module_for_attr(resource_module, attr_name) do
        {:ok, related_module} ->
          case Helpers.find_referenced_resource(value, related_module, created_structs) do
            {:ok, resource} ->
              # Return the struct itself for struct mode, not the ID
              {:ok, resource}

            :not_found ->
              # Keep as atom if not found
              {:ok, value}
          end

        :error ->
          {:ok, value}
      end
    else
      # Not a relationship, keep as-is
      {:ok, value}
    end
  end

  defp resolve_struct_attribute_value(value, _attr_name, _resource_module, _created_structs),
    do: {:ok, value}

  # Create a struct without database persistence
  defp create_struct(resource_module, attributes, _opts) do
    # Get primary key field(s)
    primary_key = Ash.Resource.Info.primary_key(resource_module)

    # Generate ID if needed and not provided
    attributes_with_id =
      case {primary_key, Map.has_key?(attributes, :id)} do
        {[:id], false} ->
          Map.put(attributes, :id, Ash.UUID.generate())

        _ ->
          attributes
      end

    # Add timestamps if the resource has them and they're not provided
    now = DateTime.utc_now()

    attributes_with_timestamps =
      attributes_with_id
      |> maybe_add_timestamp(:inserted_at, now, resource_module)
      |> maybe_add_timestamp(:updated_at, now, resource_module)

    # Create the struct
    struct = struct(resource_module, attributes_with_timestamps)

    {:ok, struct}
  rescue
    error ->
      {:error, "Failed to build struct: #{inspect(error)}"}
  end

  defp maybe_add_timestamp(attributes, field, default_value, resource_module) do
    if Map.has_key?(attributes, field) do
      attributes
    else
      # Check if the resource has this timestamp field
      case Ash.Resource.Info.attribute(resource_module, field) do
        nil -> attributes
        _attr -> Map.put(attributes, field, default_value)
      end
    end
  end
end
