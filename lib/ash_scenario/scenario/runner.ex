defmodule AshScenario.Scenario.Runner do
  @moduledoc """
  Executes resources and creates Ash resources with dependency resolution.
  """

  alias AshScenario.Scenario.Registry
  require Logger
  alias AshScenario.Log

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
    {normalized_refs, overrides_map} = normalize_refs_and_overrides(prototype_refs, opts)

    debug_refs = Enum.map(normalized_refs, fn {m, r} -> {m, r} end)
    Log.debug(
      fn -> "run_prototypes start refs=#{inspect(debug_refs)} overrides=#{inspect(overrides_map)} opts=#{inspect(Keyword.drop(opts, [:__overrides_map__]))}" end,
      component: :runner, trace_id: trace
    )

    with {:ok, ordered_prototypes} <- Registry.resolve_dependencies(normalized_refs) do
      Log.debug(
        fn -> "dependency_order=#{Enum.map(ordered_prototypes, &{&1.resource, &1.ref}) |> inspect()}" end,
        component: :runner, trace_id: trace
      )
      Enum.reduce_while(ordered_prototypes, {:ok, %{}}, fn prototype, {:ok, created_resources} ->
        case execute_prototype(prototype, Keyword.put(opts, :__overrides_map__, overrides_map), created_resources) do
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
              component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
            )
            {:halt, {:error, reason}}
        end
      end)
      |> tap(fn _ ->
        duration = System.monotonic_time(:millisecond) - started_at
        Log.info(fn -> "run_prototypes finished duration_ms=#{duration}" end, component: :runner, trace_id: trace)
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
    domain = Keyword.get(opts, :domain) || infer_domain(prototype.resource)
    Log.debug(
      fn -> "execute_prototype start module=#{inspect(prototype.resource)} ref=#{prototype.ref} domain=#{inspect(domain)}" end,
      component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
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

    with {:ok, resolved_attributes} <- resolve_attributes(merged_attributes, prototype.resource, created_resources) do
      module_cfg = AshScenario.Info.create(prototype.resource)
      res_fn = Map.get(prototype, :function)
      res_action = Map.get(prototype, :action)

      cond do
        # Per-resource custom function override
        res_fn != nil ->
          Log.debug(
            fn -> "using_custom_function (prototype override) module=#{inspect(prototype.resource)} ref=#{prototype.ref} function=#{inspect(res_fn)}" end,
            component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
          )
          case execute_custom_function(res_fn, resolved_attributes, opts) do
            {:ok, created_resource} ->
              track_created_resource(created_resource, prototype)
              Log.info(
                fn -> "custom_function_success module=#{inspect(prototype.resource)} ref=#{prototype.ref} id=#{Map.get(created_resource, :id)}" end,
                component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
              )
              {:ok, created_resource}
            {:error, error} ->
              Log.error(
                fn -> "custom_function_failed module=#{inspect(prototype.resource)} ref=#{prototype.ref} error=#{inspect(error)}" end,
                component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
              )
              {:error, "Failed to create #{inspect(prototype.resource)} with custom function: #{inspect(error)}"}
          end

        # Per-resource action override (takes precedence over module-level function)
        res_action != nil ->
          Log.debug(
            fn -> "using_action (prototype override) module=#{inspect(prototype.resource)} ref=#{prototype.ref} action=#{inspect(res_action)}" end,
            component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
          )
          with {:ok, create_action} <- get_create_action(prototype.resource, res_action),
               {:ok, changeset} <- build_changeset(prototype.resource, create_action, resolved_attributes) do
            case Ash.create(changeset, domain: domain) do
              {:ok, created_resource} ->
                track_created_resource(created_resource, prototype)
                Log.info(
                  fn -> "create_success module=#{inspect(prototype.resource)} ref=#{prototype.ref} action=#{create_action} id=#{Map.get(created_resource, :id)}" end,
                  component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
                )
                {:ok, created_resource}
              {:error, error} ->
                Log.error(
                  fn -> "create_failed module=#{inspect(prototype.resource)} ref=#{prototype.ref} action=#{create_action} error=#{inspect(error)}" end,
                  component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
                )
                {:error, "Failed to create #{inspect(prototype.resource)}: #{inspect(error)}"}
            end
          end

        # Module-level custom function
        module_cfg.function != nil ->
          Log.debug(
            fn -> "using_custom_function (module-level) module=#{inspect(prototype.resource)} ref=#{prototype.ref} function=#{inspect(module_cfg.function)}" end,
            component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
          )
          case execute_custom_function(module_cfg.function, resolved_attributes, opts) do
            {:ok, created_resource} ->
              track_created_resource(created_resource, prototype)
              Log.info(
                fn -> "custom_function_success module=#{inspect(prototype.resource)} ref=#{prototype.ref} id=#{Map.get(created_resource, :id)}" end,
                component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
              )
              {:ok, created_resource}
            {:error, error} ->
              Log.error(
                fn -> "custom_function_failed module=#{inspect(prototype.resource)} ref=#{prototype.ref} error=#{inspect(error)}" end,
                component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
              )
              {:error, "Failed to create #{inspect(prototype.resource)} with custom function: #{inspect(error)}"}
          end

        true ->
          # Default Ash.create, using module-level preferred action or :create
          action = module_cfg.action || :create
          Log.debug(
            fn -> "using_default_create module=#{inspect(prototype.resource)} ref=#{prototype.ref} action=#{inspect(action)}" end,
            component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
          )
          with {:ok, create_action} <- get_create_action(prototype.resource, action),
               {:ok, changeset} <- build_changeset(prototype.resource, create_action, resolved_attributes) do
            case Ash.create(changeset, domain: domain) do
              {:ok, created_resource} ->
                track_created_resource(created_resource, prototype)
                Log.info(
                  fn -> "create_success module=#{inspect(prototype.resource)} ref=#{prototype.ref} action=#{create_action} id=#{Map.get(created_resource, :id)}" end,
                  component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
                )
                {:ok, created_resource}
              {:error, error} ->
                Log.error(
                  fn -> "create_failed module=#{inspect(prototype.resource)} ref=#{prototype.ref} action=#{create_action} error=#{inspect(error)}" end,
                  component: :runner, resource: prototype.resource, ref: prototype.ref, trace_id: trace
                )
                {:error, "Failed to create #{inspect(prototype.resource)}: #{inspect(error)}"}
            end
          end
      end
    end
  end

  # Normalize inputs and gather overrides
  defp normalize_refs_and_overrides(prototype_refs, opts) do
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
          %{{only_mod, only_ref} => top_level}
        is_map(top_level) ->
          # Must be a map keyed by {Module, :ref}
          top_level
        true ->
          %{}
      end

    {normalized_refs, Map.merge(tuple_overrides, top_overrides)}
  end

  defp resolve_attributes(attributes, resource_module, created_resources) do
    Log.debug(
      fn -> "resolve_attributes module=#{inspect(resource_module)} attrs=#{inspect(attributes)}" end,
      component: :runner, resource: resource_module
    )
    resolved = 
      attributes
      |> Enum.map(fn {key, value} ->
        {:ok, resolved_value} = resolve_attribute_value(value, key, resource_module, created_resources)
        {key, resolved_value}
      end)
      |> Map.new()
    
    {:ok, resolved}
  end

  defp resolve_attribute_value(value, attr_name, resource_module, created_resources) when is_atom(value) do
    # Only resolve atoms that correspond to relationship attributes
    if is_relationship_attribute?(resource_module, attr_name) do
      case related_module_for_attr(resource_module, attr_name) do
        {:ok, related_module} ->
          case find_referenced_resource(value, related_module, created_resources) do
            {:ok, resource} ->
              Log.debug(
                fn -> "resolved_relationship attr=#{attr_name} value=#{value} -> id=#{Map.get(resource, :id)} related_module=#{inspect(related_module)}" end,
                component: :runner, resource: resource_module
              )
              {:ok, resource.id}
            :not_found ->
              Log.debug(
                fn -> "unresolved_relationship attr=#{attr_name} value=#{value} (keeping as atom) related_module=#{inspect(related_module)}" end,
                component: :runner, resource: resource_module
              )
              {:ok, value}
          end

        :error ->
          # Relationship not found (unexpected) — preserve original value
          Log.warn(
            fn -> "relationship_not_found attr=#{attr_name} value=#{inspect(value)} (keeping as-is)" end,
            component: :runner, resource: resource_module
          )
          {:ok, value}
      end
    else
      # Not a relationship attribute, keep the atom value as-is
      Log.debug(
        fn -> "non_relationship_atom attr=#{attr_name} value=#{inspect(value)}" end,
        component: :runner, resource: resource_module
      )
      {:ok, value}
    end
  end

  defp resolve_attribute_value(value, _attr_name, _resource_module, _created_resources), do: {:ok, value}

  defp is_relationship_attribute?(resource_module, attr_name) do
    try do
      resource_module
      |> Ash.Resource.Info.relationships()
      |> Enum.any?(fn rel -> 
        rel.source_attribute == attr_name
      end)
    rescue
      _ -> false
    end
  end

  defp execute_custom_function({module, function, extra_args}, resolved_attributes, opts) do
    try do
      apply(module, function, [resolved_attributes, opts] ++ extra_args)
    rescue
      error -> {:error, "Custom function failed: #{inspect(error)}"}
    end
  end

  defp execute_custom_function(fun, resolved_attributes, opts) when is_function(fun, 2) do
    try do
      fun.(resolved_attributes, opts)
    rescue
      error -> {:error, "Custom function failed: #{inspect(error)}"}
    end
  end

  defp execute_custom_function(fun, _resolved_attributes, _opts) do
    {:error, "Invalid custom function. Must be {module, function, args} or a 2-arity function, got: #{inspect(fun)}"}
  end

  defp find_referenced_resource(resource_name, related_module, created_resources) do
    # Look for a created resource for the specific related module and name
    case Map.get(created_resources, {related_module, resource_name}) do
      nil -> :not_found
      resource -> {:ok, resource}
    end
  end

  defp related_module_for_attr(resource_module, attr_name) do
    try do
      case Enum.find(Ash.Resource.Info.relationships(resource_module), fn rel -> rel.source_attribute == attr_name end) do
        nil -> :error
        rel -> {:ok, rel.destination}
      end
    rescue
      _ -> :error
    end
  end

  defp infer_domain(resource_module) do
    try do
      Ash.Resource.Info.domain(resource_module)
    rescue
      _ -> nil
    end
  end

  defp get_create_action(resource_module, preferred_action) do
    actions = Ash.Resource.Info.actions(resource_module)
    
    case Enum.find(actions, fn action -> action.type == :create and action.name == preferred_action end) do
      nil ->
        # Fallback to any create action if specific not found
        case Enum.find(actions, fn action -> action.type == :create end) do
          nil -> {:error, "No create action found for #{inspect(resource_module)}"}
          action -> {:ok, action.name}
        end
      action -> {:ok, action.name}
    end
  end


  defp build_changeset(resource_module, action_name, attributes) do
    try do
      changeset = 
        resource_module
        |> Ash.Changeset.for_create(action_name, attributes)
      
      {:ok, changeset}
    rescue
      error -> {:error, "Failed to build changeset: #{inspect(error)}"}
    end
  end

  defp track_created_resource(created_resource, prototype) do
    # Integration point with existing telemetry handler
    # The telemetry handler should already be tracking resource creation
    # We could emit additional events here if needed for resource-specific tracking
    :telemetry.execute(
      [:ash_scenario, :resource, :created],
      %{count: 1},
      %{resource: created_resource, resource_name: prototype.ref, resource_module: prototype.resource}
    )
  end
end
