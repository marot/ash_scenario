defmodule AshScenario.Scenario.Helpers do
  @moduledoc """
  Shared helper functions for resource creation, used by both Runner and StructBuilder.
  """

  alias AshScenario.Log
  require Logger

  @doc """
  Normalize prototype refs and merge overrides from multiple sources.

  Supports:
  - Per-ref tuple: {Module, :ref, %{attr => value}}
  - Top-level opts: overrides: %{{Module, :ref} => %{...}}
  - For a single prototype, a bare map is allowed: overrides: %{...}
  """
  def normalize_refs_and_overrides(prototype_refs, opts) do
    {normalized_refs, tuple_overrides} =
      Enum.reduce(prototype_refs, {[], %{}}, fn
        {mod, ref, overrides}, {refs, acc} when is_map(overrides) ->
          {[{mod, ref} | refs], Map.put(acc, {mod, ref}, overrides)}

        {mod, ref}, {refs, acc} ->
          {[{mod, ref} | refs], acc}

        other, acc ->
          # Keep behavior predictable: ignore malformed entries but log in debug
          Logger.debug("Ignoring malformed prototype ref: #{inspect(other)}")
          acc
      end)

    normalized_refs = Enum.reverse(normalized_refs)

    top_level = Keyword.get(opts, :overrides)
    # For single prototype calls, allow a bare map
    top_overrides =
      cond do
        is_map(top_level) and length(normalized_refs) == 1 ->
          [{only_mod, only_ref}] = normalized_refs
          # Check if it's already keyed by the prototype ref
          if Map.has_key?(top_level, {only_mod, only_ref}) do
            # Already properly keyed, use as-is
            top_level
          else
            # Bare map of attributes, wrap it
            %{{only_mod, only_ref} => top_level}
          end

        is_map(top_level) ->
          # Must be a map keyed by {Module, :ref}
          top_level

        true ->
          %{}
      end

    {normalized_refs, Map.merge(tuple_overrides, top_overrides)}
  end

  @doc """
  Resolve all attributes, handling relationship references.
  """
  def resolve_attributes(attributes, resource_module, created_resources) do
    Log.debug(
      fn ->
        "resolve_attributes module=#{inspect(resource_module)} attrs=#{inspect(attributes)}"
      end,
      component: :helpers,
      resource: resource_module
    )

    resolved =
      attributes
      |> Enum.map(fn {key, value} ->
        {:ok, resolved_value} =
          resolve_attribute_value(value, key, resource_module, created_resources)

        {key, resolved_value}
      end)
      |> Map.new()

    {:ok, resolved}
  end

  @doc """
  Resolve a single attribute value, handling relationship references.

  For database mode: Resolves atom references to IDs from created resources.
  For struct mode: Keep atom references as-is (handled by caller).
  """
  def resolve_attribute_value(value, attr_name, resource_module, created_resources)
      when is_atom(value) do
    # Only resolve atoms that correspond to relationship attributes
    if relationship_attribute?(resource_module, attr_name) do
      case related_module_for_attr(resource_module, attr_name) do
        {:ok, related_module} ->
          case find_referenced_resource(value, related_module, created_resources) do
            {:ok, resource} ->
              Log.debug(
                fn ->
                  "resolved_relationship attr=#{attr_name} value=#{value} -> id=#{Map.get(resource, :id)} related_module=#{inspect(related_module)}"
                end,
                component: :helpers,
                resource: resource_module
              )

              {:ok, resource.id}

            :not_found ->
              Log.debug(
                fn ->
                  "unresolved_relationship attr=#{attr_name} value=#{value} (keeping as atom) related_module=#{inspect(related_module)}"
                end,
                component: :helpers,
                resource: resource_module
              )

              {:ok, value}
          end

        :error ->
          # Relationship not found (unexpected) — preserve original value
          Log.warn(
            fn ->
              "relationship_not_found attr=#{attr_name} value=#{inspect(value)} (keeping as-is)"
            end,
            component: :helpers,
            resource: resource_module
          )

          {:ok, value}
      end
    else
      # Not a relationship attribute, keep the atom value as-is
      Log.debug(
        fn -> "non_relationship_atom attr=#{attr_name} value=#{inspect(value)}" end,
        component: :helpers,
        resource: resource_module
      )

      {:ok, value}
    end
  end

  def resolve_attribute_value(value, _attr_name, _resource_module, _created_resources),
    do: {:ok, value}

  @doc """
  Check if an attribute name corresponds to a relationship.
  """
  def relationship_attribute?(resource_module, attr_name) do
    resource_module
    |> Ash.Resource.Info.relationships()
    |> Enum.any?(fn rel ->
      rel.source_attribute == attr_name
    end)
  rescue
    _ -> false
  end

  @doc """
  Get the related module for a relationship attribute.
  """
  def related_module_for_attr(resource_module, attr_name) do
    case Enum.find(Ash.Resource.Info.relationships(resource_module), fn rel ->
           rel.source_attribute == attr_name
         end) do
      nil -> :error
      rel -> {:ok, rel.destination}
    end
  rescue
    _ -> :error
  end

  @doc """
  Find a referenced resource in the created resources map.
  """
  def find_referenced_resource(resource_name, related_module, created_resources) do
    # Look for a created resource for the specific related module and name
    case Map.get(created_resources, {related_module, resource_name}) do
      nil -> :not_found
      resource -> {:ok, resource}
    end
  end

  @doc """
  Infer the domain for a resource module.
  """
  def infer_domain(resource_module) do
    Ash.Resource.Info.domain(resource_module)
  rescue
    _ -> nil
  end

  @doc """
  Execute a custom creation function.
  """
  def execute_custom_function({module, function, extra_args}, resolved_attributes, opts) do
    apply(module, function, [resolved_attributes, opts] ++ extra_args)
  rescue
    error -> {:error, "Custom function failed: #{inspect(error)}"}
  end

  def execute_custom_function(fun, resolved_attributes, opts) when is_function(fun, 2) do
    fun.(resolved_attributes, opts)
  rescue
    error -> {:error, "Custom function failed: #{inspect(error)}"}
  end

  def execute_custom_function(fun, _resolved_attributes, _opts) do
    {:error,
     "Invalid custom function. Must be {module, function, args} or a 2-arity function, got: #{inspect(fun)}"}
  end

  @doc """
  Get a create action for a resource, with fallback to any create action.
  """
  def get_create_action(resource_module, preferred_action) do
    actions = Ash.Resource.Info.actions(resource_module)

    case Enum.find(actions, fn action ->
           action.type == :create and action.name == preferred_action
         end) do
      nil ->
        # Fallback to any create action if specific not found
        case Enum.find(actions, fn action -> action.type == :create end) do
          nil -> {:error, "No create action found for #{inspect(resource_module)}"}
          action -> {:ok, action.name}
        end

      action ->
        {:ok, action.name}
    end
  end

  @doc """
  Track telemetry for a created resource.
  """
  def track_created_resource(created_resource, prototype) do
    :telemetry.execute(
      [:ash_scenario, :resource, :created],
      %{count: 1},
      %{
        resource: created_resource,
        resource_name: prototype.ref,
        resource_module: prototype.resource
      }
    )
  end

  @doc """
  Build a changeset for creating a resource with Ash.

  Returns `{:ok, changeset, tenant_value}` where tenant_value may be nil
  if the resource doesn't use attribute-based multitenancy.
  """
  def build_changeset(resource_module, action_name, attributes, _opts) do
    # Drop nil values
    sanitized_attributes =
      attributes
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    # Extract tenant information if resource uses attribute multitenancy
    {:ok, tenant_value, clean_attributes} =
      AshScenario.Multitenancy.extract_tenant_info(resource_module, sanitized_attributes)

    Log.debug(
      fn ->
        "build_changeset resource=#{inspect(resource_module)} action=#{inspect(action_name)} attrs_in=#{inspect(attributes)} sanitized=#{inspect(sanitized_attributes)} tenant=#{inspect(tenant_value)} clean_attrs=#{inspect(clean_attributes)}"
      end,
      component: :helpers,
      resource: resource_module
    )

    changeset =
      resource_module
      |> Ash.Changeset.for_create(action_name, clean_attributes)

    Log.debug(
      fn ->
        "built_changeset resource=#{inspect(resource_module)} action=#{inspect(action_name)} changes=#{inspect(Map.get(changeset, :changes, %{}))} tenant=#{inspect(tenant_value)}"
      end,
      component: :helpers,
      resource: resource_module
    )

    {:ok, changeset, tenant_value}
  rescue
    error -> {:error, "Failed to build changeset: #{inspect(error)}"}
  end

  @doc """
  Create a resource using either a custom function or Ash.create, with proper tenant handling.
  This is the common path for both Runner and Scenario DSL.
  """
  def create_resource_with_tenant(module, resolved_attributes, opts, create_cfg \\ nil) do
    # Get create configuration if not provided
    create_cfg = create_cfg || AshScenario.Info.create(module)

    # Extract tenant info if the resource uses multitenancy
    {:ok, tenant_value, _clean_attributes} =
      AshScenario.Multitenancy.extract_tenant_info(module, resolved_attributes)

    # Add tenant to opts
    opts_with_tenant = AshScenario.Multitenancy.add_tenant_to_opts(opts, tenant_value)

    # Execute creation via custom function or Ash.create
    if create_cfg.function do
      execute_custom_function(create_cfg.function, resolved_attributes, opts_with_tenant)
    else
      domain = Keyword.get(opts_with_tenant, :domain) || infer_domain(module)

      with {:ok, create_action} <- get_create_action(module, create_cfg.action || :create),
           {:ok, changeset, _tenant} <-
             build_changeset(module, create_action, resolved_attributes, opts_with_tenant) do
        create_opts = AshScenario.Multitenancy.add_tenant_to_opts([domain: domain], tenant_value)

        case Ash.create(changeset, create_opts) do
          {:ok, resource} -> {:ok, resource}
          {:error, error} -> {:error, "Failed to create #{inspect(module)}: #{inspect(error)}"}
        end
      end
    end
  end
end
