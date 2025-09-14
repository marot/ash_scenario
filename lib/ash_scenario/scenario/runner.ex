defmodule AshScenario.Scenario.Runner do
  @moduledoc """
  Executes resources and creates Ash resources with dependency resolution.
  """

  alias AshScenario.Log
  alias AshScenario.Scenario.{Helpers, Registry}
  require Logger

  @doc """
  Run a single prototype by name from an Ash resource module.

  Note: This function automatically resolves and creates all dependencies.
  """
  def run_prototype(resource_module, prototype_name, opts \\ []) do
    case run_prototypes([{resource_module, prototype_name}], opts) do
      {:ok, created} -> {:ok, created[{resource_module, prototype_name}]}
      error -> error
    end
  end

  @doc """
  Run multiple prototypes with dependency resolution.
  """
  def run_prototypes(prototype_refs, opts \\ []) when is_list(prototype_refs) do
    {opts, trace} = Log.ensure_trace(opts)
    started_at = System.monotonic_time(:millisecond)

    # Support first-class overrides in two forms:
    # - Per-ref tuple: {Module, :ref, %{attr => value}}
    # - Top-level opts: overrides: %{{Module, :ref} => %{...}}
    #   For a single prototype, a bare map is allowed: overrides: %{...}
    {normalized_refs, overrides_map} = Helpers.normalize_refs_and_overrides(prototype_refs, opts)

    debug_refs = Enum.map(normalized_refs, fn {m, r} -> {m, r} end)

    Log.debug(
      fn ->
        "run_prototypes start refs=#{inspect(debug_refs)} overrides=#{inspect(overrides_map)} opts=#{inspect(Keyword.drop(opts, [:__overrides_map__]))}"
      end,
      component: :runner,
      trace_id: trace
    )

    with {:ok, ordered_prototypes} <- Registry.resolve_dependencies(normalized_refs) do
      Log.debug(
        fn ->
          "dependency_order=#{Enum.map(ordered_prototypes, &{&1.resource, &1.ref}) |> inspect()}"
        end,
        component: :runner,
        trace_id: trace
      )

      Enum.reduce_while(ordered_prototypes, {:ok, %{}}, fn prototype, {:ok, created_resources} ->
        case execute_prototype(
               prototype,
               Keyword.put(opts, :__overrides_map__, overrides_map),
               created_resources
             ) do
          {:ok, created_resource} ->
            key = {prototype.resource, prototype.ref}
            created_resources = Map.put(created_resources, key, created_resource)

            # Also index by the actual struct module returned, to support custom functions
            struct_mod = created_resource.__struct__

            created_resources =
              if struct_mod != prototype.resource do
                Map.put(created_resources, {struct_mod, prototype.ref}, created_resource)
              else
                created_resources
              end

            {:cont, {:ok, created_resources}}

          {:error, reason} ->
            Log.error(
              fn ->
                "run_prototypes halted module=#{inspect(prototype.resource)} ref=#{prototype.ref} reason=#{inspect(reason)}"
              end,
              component: :runner,
              resource: prototype.resource,
              ref: prototype.ref,
              trace_id: trace
            )

            {:halt, {:error, reason}}
        end
      end)
      |> tap(fn _ ->
        duration = System.monotonic_time(:millisecond) - started_at

        Log.info(fn -> "run_prototypes finished duration_ms=#{duration}" end,
          component: :runner,
          trace_id: trace
        )
      end)
    end
  end

  @doc """
  Run all prototypes defined for a resource module.
  """
  def run_all_prototypes(resource_module, opts \\ []) do
    prototypes = Registry.get_prototypes(resource_module)
    prototype_refs = Enum.map(prototypes, fn r -> {r.resource, r.ref} end)
    run_prototypes(prototype_refs, opts)
  end

  # Deprecated scenario-named functions removed. Use run_prototype(s) instead.

  # Private Functions

  defp execute_prototype(prototype, opts, created_resources) do
    {opts, trace} = Log.ensure_trace(opts)
    domain = Keyword.get(opts, :domain) || Helpers.infer_domain(prototype.resource)

    Log.debug(
      fn ->
        "execute_prototype start module=#{inspect(prototype.resource)} ref=#{prototype.ref} domain=#{inspect(domain)}"
      end,
      component: :runner,
      resource: prototype.resource,
      ref: prototype.ref,
      trace_id: trace
    )

    with {:ok, attributes, explicit_nil_keys} <- prepare_attributes(prototype, opts),
         {:ok, resolved_attributes} <-
           Helpers.resolve_attributes(attributes, prototype.resource, created_resources) do
      execution_context = %{
        prototype: prototype,
        resolved_attributes: resolved_attributes,
        explicit_nil_keys: explicit_nil_keys,
        opts: opts,
        domain: domain,
        trace: trace
      }

      execute_by_strategy(execution_context)
    end
  end

  defp prepare_attributes(prototype, opts) do
    overrides_map = Keyword.get(opts, :__overrides_map__, %{})
    per_ref_overrides = Map.get(overrides_map, {prototype.resource, prototype.ref}, %{})

    base_attributes = normalize_attributes(prototype.attributes)
    merged_attributes = Map.merge(base_attributes, per_ref_overrides)

    explicit_nil_keys =
      per_ref_overrides
      |> Enum.filter(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(&elem(&1, 0))

    {:ok, merged_attributes, explicit_nil_keys}
  end

  defp normalize_attributes(attributes) when is_map(attributes), do: attributes
  defp normalize_attributes(attributes) when is_list(attributes), do: Map.new(attributes)
  defp normalize_attributes(nil), do: %{}
  defp normalize_attributes(_), do: %{}

  defp execute_by_strategy(%{prototype: prototype} = context) do
    module_config = AshScenario.Info.create(prototype.resource)
    prototype_function = Map.get(prototype, :function)
    prototype_action = Map.get(prototype, :action)

    cond do
      prototype_function != nil ->
        execute_with_custom_function(context, prototype_function, :prototype)

      prototype_action != nil ->
        execute_with_action(context, prototype_action, :prototype)

      module_config.function != nil ->
        execute_with_custom_function(context, module_config.function, :module)

      true ->
        action = module_config.action || :create
        execute_with_action(context, action, :default)
    end
  end

  defp execute_with_custom_function(context, function, level) do
    %{
      prototype: prototype,
      resolved_attributes: resolved_attributes,
      opts: opts,
      trace: trace
    } = context

    # Extract tenant info for custom functions
    {:ok, tenant_value, _clean_attributes} =
      AshScenario.Multitenancy.extract_tenant_info(prototype.resource, resolved_attributes)

    # Add tenant to opts for custom functions
    opts_with_tenant = AshScenario.Multitenancy.add_tenant_to_opts(opts, tenant_value)

    Log.debug(
      fn ->
        level_desc = if level == :prototype, do: " (prototype override)", else: " (module-level)"

        "using_custom_function#{level_desc} module=#{inspect(prototype.resource)} ref=#{prototype.ref} function=#{inspect(function)} tenant=#{inspect(tenant_value)}"
      end,
      component: :runner,
      resource: prototype.resource,
      ref: prototype.ref,
      trace_id: trace
    )

    case Helpers.execute_custom_function(function, resolved_attributes, opts_with_tenant) do
      {:ok, created_resource} ->
        handle_creation_success(created_resource, prototype, trace, :custom_function)

      {:error, error} ->
        handle_creation_error(error, prototype, trace, :custom_function)
    end
  end

  defp execute_with_action(context, action, level) do
    %{
      prototype: prototype,
      resolved_attributes: resolved_attributes,
      explicit_nil_keys: explicit_nil_keys,
      opts: opts,
      domain: domain,
      trace: trace
    } = context

    Log.debug(
      fn ->
        level_desc =
          case level do
            :prototype -> " (prototype override)"
            :default -> ""
          end

        "using_action#{level_desc} module=#{inspect(prototype.resource)} ref=#{prototype.ref} action=#{inspect(action)}"
      end,
      component: :runner,
      resource: prototype.resource,
      ref: prototype.ref,
      trace_id: trace
    )

    with {:ok, create_action} <- Helpers.get_create_action(prototype.resource, action),
         {:ok, changeset, tenant_value} <-
           Helpers.build_changeset(
             prototype.resource,
             create_action,
             resolved_attributes,
             Keyword.put(opts, :__explicit_nil_keys__, explicit_nil_keys)
           ) do
      create_opts = AshScenario.Multitenancy.add_tenant_to_opts([domain: domain], tenant_value)

      case Ash.create(changeset, create_opts) do
        {:ok, created_resource} ->
          handle_creation_success(created_resource, prototype, trace, create_action)

        {:error, error} ->
          handle_creation_error(error, prototype, trace, create_action)
      end
    end
  end

  defp handle_creation_success(created_resource, prototype, trace, method) do
    Helpers.track_created_resource(created_resource, prototype)

    Log.info(
      fn ->
        method_desc = if is_atom(method), do: "action=#{method}", else: "method=#{method}"

        "create_success module=#{inspect(prototype.resource)} ref=#{prototype.ref} #{method_desc} id=#{Map.get(created_resource, :id)}"
      end,
      component: :runner,
      resource: prototype.resource,
      ref: prototype.ref,
      trace_id: trace
    )

    {:ok, created_resource}
  end

  defp handle_creation_error(error, prototype, trace, method) do
    Log.error(
      fn ->
        method_desc = if is_atom(method), do: "action=#{method}", else: "method=#{method}"

        "create_failed module=#{inspect(prototype.resource)} ref=#{prototype.ref} #{method_desc} error=#{inspect(error)}"
      end,
      component: :runner,
      resource: prototype.resource,
      ref: prototype.ref,
      trace_id: trace
    )

    error_context =
      case method do
        :custom_function -> " with custom function"
        method when is_atom(method) -> ""
        _ -> " with #{method}"
      end

    {:error, "Failed to create #{inspect(prototype.resource)}#{error_context}: #{inspect(error)}"}
  end
end
