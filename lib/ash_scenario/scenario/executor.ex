defmodule AshScenario.Scenario.Executor do
  @moduledoc """
  Shared execution logic for creating resources from prototypes.

  This module contains the common execution logic used by both Runner (database persistence)
  and StructBuilder (struct creation without persistence). It uses a strategy pattern to
  delegate the actual resource creation to different implementations.
  """

  alias AshScenario.Scenario.Helpers
  require Logger

  @doc """
  Defines the behaviour that execution strategies must implement.
  """
  @callback create_resource(module :: module(), attributes :: map(), opts :: keyword()) ::
              {:ok, struct()} | {:error, any()}

  @callback wrap_execution(
              prototypes :: list(),
              opts :: keyword(),
              execution_fn :: function()
            ) :: {:ok, map()} | {:error, any()}

  @doc """
  Execute a list of prototypes using the specified strategy.

  ## Parameters

    * `prototype_refs` - List of prototype references to execute
    * `opts` - Options for execution
    * `strategy` - Module implementing the execution strategy behaviour

  ## Returns

    * `{:ok, map()}` - Map of created resources keyed by {module, ref}
    * `{:error, reason}` - Error if execution fails
  """
  def execute_prototypes(prototype_refs, opts, strategy) when is_list(prototype_refs) do
    {normalized_refs, overrides_map} = Helpers.normalize_refs_and_overrides(prototype_refs, opts)

    # Extract additional dependencies from overrides (like actor references)
    additional_refs = extract_override_dependencies(overrides_map)
    all_refs = Enum.uniq(normalized_refs ++ additional_refs)

    with {:ok, ordered_prototypes} <-
           AshScenario.Scenario.Registry.resolve_dependencies(all_refs) do
      execution_fn = fn ->
        execute_ordered_prototypes(
          ordered_prototypes,
          Keyword.put(opts, :__overrides_map__, overrides_map),
          strategy
        )
      end

      strategy.wrap_execution(ordered_prototypes, opts, execution_fn)
    end
  end

  defp extract_override_dependencies(overrides_map) do
    overrides_map
    |> Enum.flat_map(fn {_ref, overrides} ->
      overrides
      |> Enum.filter(fn
        {:actor, {_module, _ref}} -> true
        {:actor, value} when is_atom(value) and not is_nil(value) -> true
        _ -> false
      end)
      |> Enum.map(fn {:actor, value} ->
        case value do
          {module, ref} -> {module, ref}
          # Just the atom - will be resolved globally
          ref when is_atom(ref) -> ref
        end
      end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Execute a single prototype and return the created resource.
  """
  def execute_single_prototype(resource_module, prototype_name, opts, strategy) do
    case execute_prototypes([{resource_module, prototype_name}], opts, strategy) do
      {:ok, created} -> {:ok, created[{resource_module, prototype_name}]}
      error -> error
    end
  end

  @doc """
  Execute all prototypes defined for a resource module.
  """
  def execute_all_prototypes(resource_module, opts, strategy) do
    prototypes = AshScenario.Scenario.Registry.get_prototypes(resource_module)
    prototype_refs = Enum.map(prototypes, fn r -> {r.resource, r.ref} end)
    execute_prototypes(prototype_refs, opts, strategy)
  end

  # Private Functions

  defp execute_ordered_prototypes(ordered_prototypes, opts, strategy) do
    Enum.reduce_while(ordered_prototypes, {:ok, %{}}, fn prototype, {:ok, created_resources} ->
      case execute_prototype(prototype, opts, created_resources, strategy) do
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
          {:halt, {:error, reason}}
      end
    end)
  end

  defp execute_prototype(prototype, opts, created_resources, strategy) do
    domain = Keyword.get(opts, :domain) || Helpers.infer_domain(prototype.resource)

    with {:ok, attributes, explicit_nil_keys} <- prepare_attributes(prototype, opts),
         {:ok, resolved_attributes} <-
           resolve_attributes(attributes, prototype.resource, created_resources, strategy) do
      execution_context = %{
        prototype: prototype,
        resolved_attributes: resolved_attributes,
        explicit_nil_keys: explicit_nil_keys,
        opts: opts,
        domain: domain,
        strategy: strategy
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

  defp resolve_attributes(attributes, resource_module, created_resources, strategy) do
    # Use strategy-specific resolution if available
    if function_exported?(strategy, :resolve_attributes, 3) do
      strategy.resolve_attributes(attributes, resource_module, created_resources)
    else
      # Default resolution for database strategy
      Helpers.resolve_attributes(attributes, resource_module, created_resources)
    end
  end

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

  defp execute_with_custom_function(context, function, _level) do
    %{
      prototype: prototype,
      resolved_attributes: resolved_attributes,
      opts: opts,
      strategy: _strategy
    } = context

    # Extract tenant info for custom functions
    {:ok, tenant_value, _clean_attributes} =
      AshScenario.Multitenancy.extract_tenant_info(prototype.resource, resolved_attributes)

    # Add tenant to opts for custom functions
    opts_with_tenant = AshScenario.Multitenancy.add_tenant_to_opts(opts, tenant_value)

    case Helpers.execute_custom_function(function, resolved_attributes, opts_with_tenant) do
      {:ok, created_resource} ->
        handle_creation_success(created_resource, prototype, :custom_function)

      {:error, error} ->
        handle_creation_error(error, prototype, :custom_function)
    end
  end

  defp execute_with_action(context, action, _level) do
    %{
      prototype: prototype,
      resolved_attributes: resolved_attributes,
      explicit_nil_keys: explicit_nil_keys,
      opts: opts,
      domain: domain,
      strategy: strategy
    } = context

    opts_with_nil_keys = Keyword.put(opts, :__explicit_nil_keys__, explicit_nil_keys)

    # Delegate creation to strategy - let the strategy handle tenant extraction
    case strategy.create_resource(
           prototype.resource,
           resolved_attributes,
           Keyword.merge(opts_with_nil_keys, domain: domain, action: action)
         ) do
      {:ok, created_resource} ->
        handle_creation_success(created_resource, prototype, action)

      {:error, error} ->
        handle_creation_error(error, prototype, action)
    end
  end

  defp handle_creation_success(created_resource, prototype, _method) do
    Helpers.track_created_resource(created_resource, prototype)
    {:ok, created_resource}
  end

  defp handle_creation_error(error, prototype, method) do
    error_context =
      case method do
        :custom_function -> " with custom function"
        method when is_atom(method) -> ""
        _ -> " with #{method}"
      end

    {:error, "Failed to create #{inspect(prototype.resource)}#{error_context}: #{inspect(error)}"}
  end
end
