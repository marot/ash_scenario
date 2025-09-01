defmodule AshScenario.Scenario.Runner do
  @moduledoc """
  Executes resources and creates Ash resources with dependency resolution.
  """

  alias AshScenario.Scenario.Registry
  require Logger
  alias AshScenario.Log

  @doc """
  Run a single resource by name from a resource.
  """
  def run_resource(resource_module, resource_name, opts \\ []) do
    {opts, trace} = Log.ensure_trace(opts)
    started_at = System.monotonic_time(:millisecond)

    Log.debug(
      fn ->
        "run_resource start module=#{inspect(resource_module)} ref=#{resource_name} opts=#{inspect(opts)}"
      end,
      component: :runner, resource: resource_module, ref: resource_name, trace_id: trace
    )

    case Registry.get_resource({resource_module, resource_name}) do
      nil -> 
        Log.warn(
          fn ->
            "resource_not_found module=#{inspect(resource_module)} ref=#{resource_name}"
          end,
          component: :runner, resource: resource_module, ref: resource_name, trace_id: trace
        )

        {:error, "Resource #{resource_name} not found in #{inspect(resource_module)}"}
      resource ->
        result = execute_resource(resource, opts)
        duration = System.monotonic_time(:millisecond) - started_at

        case result do
          {:ok, _created} ->
            Log.info(
              fn ->
                "run_resource success module=#{inspect(resource_module)} ref=#{resource_name} duration_ms=#{duration}"
              end,
              component: :runner, resource: resource_module, ref: resource_name, trace_id: trace
            )

          {:error, reason} ->
            Log.error(
              fn ->
                "run_resource error module=#{inspect(resource_module)} ref=#{resource_name} duration_ms=#{duration} reason=#{inspect(reason)}"
              end,
              component: :runner, resource: resource_module, ref: resource_name, trace_id: trace
            )
        end

        result
    end
  end

  @doc """
  Run multiple resources with dependency resolution.
  """
  def run_resources(resource_refs, opts \\ []) when is_list(resource_refs) do
    {opts, trace} = Log.ensure_trace(opts)
    started_at = System.monotonic_time(:millisecond)

    Log.debug(
      fn -> "run_resources start refs=#{inspect(resource_refs)} opts=#{inspect(opts)}" end,
      component: :runner, trace_id: trace
    )

    with {:ok, ordered_resources} <- Registry.resolve_dependencies(resource_refs) do
      Log.debug(
        fn -> "dependency_order=#{Enum.map(ordered_resources, &{&1.resource, &1.ref}) |> inspect()}" end,
        component: :runner, trace_id: trace
      )
      Enum.reduce_while(ordered_resources, {:ok, %{}}, fn resource, {:ok, created_resources} ->
        case execute_resource(resource, opts, created_resources) do
          {:ok, created_resource} -> 
            key = {resource.resource, resource.ref}
            created_resources = Map.put(created_resources, key, created_resource)

            # Also index by the actual struct module returned, to support custom functions
            struct_mod = created_resource.__struct__
            created_resources =
              if struct_mod != resource.resource do
                Map.put(created_resources, {struct_mod, resource.ref}, created_resource)
              else
                created_resources
              end

            {:cont, {:ok, created_resources}}
          {:error, reason} -> 
            Log.error(
              fn ->
                "run_resources halted module=#{inspect(resource.resource)} ref=#{resource.ref} reason=#{inspect(reason)}"
              end,
              component: :runner, resource: resource.resource, ref: resource.ref, trace_id: trace
            )
            {:halt, {:error, reason}}
        end
      end)
      |> tap(fn _ ->
        duration = System.monotonic_time(:millisecond) - started_at
        Log.info(fn -> "run_resources finished duration_ms=#{duration}" end, component: :runner, trace_id: trace)
      end)
    end
  end

  @doc """
  Run all resources for a resource.
  """
  def run_all_resources(resource_module, opts \\ []) do
    resources = Registry.get_resources(resource_module)
    resource_refs = Enum.map(resources, fn r -> {r.resource, r.ref} end)
    run_resources(resource_refs, opts)
  end

  # Backward compatibility functions
  def run_scenario(resource_module, resource_name, opts \\ []), do: run_resource(resource_module, resource_name, opts)
  def run_scenarios(resource_refs, opts \\ []), do: run_resources(resource_refs, opts)
  def run_all_scenarios(resource_module, opts \\ []), do: run_all_resources(resource_module, opts)

  # Private Functions

  defp execute_resource(resource, opts, created_resources \\ %{}) do
    {opts, trace} = Log.ensure_trace(opts)
    domain = Keyword.get(opts, :domain) || infer_domain(resource.resource)
    Log.debug(
      fn -> "execute_resource start module=#{inspect(resource.resource)} ref=#{resource.ref} domain=#{inspect(domain)}" end,
      component: :runner, resource: resource.resource, ref: resource.ref, trace_id: trace
    )
    
    with {:ok, resolved_attributes} <- resolve_attributes(resource.attributes, resource.resource, created_resources) do
      create_cfg = AshScenario.Info.create(resource.resource)

      if create_cfg.function do
        # Use custom function from module-level create config
        Log.debug(
          fn -> "using_custom_function module=#{inspect(resource.resource)} ref=#{resource.ref} function=#{inspect(create_cfg.function)}" end,
          component: :runner, resource: resource.resource, ref: resource.ref, trace_id: trace
        )
        case execute_custom_function(create_cfg.function, resolved_attributes, opts) do
          {:ok, created_resource} ->
            track_created_resource(created_resource, resource)
            Log.info(
              fn -> "custom_function_success module=#{inspect(resource.resource)} ref=#{resource.ref} id=#{Map.get(created_resource, :id)}" end,
              component: :runner, resource: resource.resource, ref: resource.ref, trace_id: trace
            )
            {:ok, created_resource}
          {:error, error} ->
            Log.error(
              fn -> "custom_function_failed module=#{inspect(resource.resource)} ref=#{resource.ref} error=#{inspect(error)}" end,
              component: :runner, resource: resource.resource, ref: resource.ref, trace_id: trace
            )
            {:error, "Failed to create #{inspect(resource.resource)} with custom function: #{inspect(error)}"}
        end
      else
        # Use default Ash.create
        action = create_cfg.action || :create
        Log.debug(
          fn -> "using_default_create module=#{inspect(resource.resource)} ref=#{resource.ref} action=#{inspect(action)}" end,
          component: :runner, resource: resource.resource, ref: resource.ref, trace_id: trace
        )
        with {:ok, create_action} <- get_create_action(resource.resource, action),
             {:ok, changeset} <- build_changeset(resource.resource, create_action, resolved_attributes) do
          
          case Ash.create(changeset, domain: domain) do
            {:ok, created_resource} -> 
              track_created_resource(created_resource, resource)
              Log.info(
                fn -> "create_success module=#{inspect(resource.resource)} ref=#{resource.ref} action=#{create_action} id=#{Map.get(created_resource, :id)}" end,
                component: :runner, resource: resource.resource, ref: resource.ref, trace_id: trace
              )
              {:ok, created_resource}
            {:error, error} -> 
              Log.error(
                fn -> "create_failed module=#{inspect(resource.resource)} ref=#{resource.ref} action=#{create_action} error=#{inspect(error)}" end,
                component: :runner, resource: resource.resource, ref: resource.ref, trace_id: trace
              )
              {:error, "Failed to create #{inspect(resource.resource)}: #{inspect(error)}"}
          end
        end
      end
    end
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
                fn -> "resolved_relationship attr=#{attr_name} value=#{value} -> id=#{get_in(resource, [:id])} related_module=#{inspect(related_module)}" end,
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

  defp track_created_resource(created_resource, resource) do
    # Integration point with existing telemetry handler
    # The telemetry handler should already be tracking resource creation
    # We could emit additional events here if needed for resource-specific tracking
    :telemetry.execute(
      [:ash_scenario, :resource, :created],
      %{count: 1},
      %{resource: created_resource, resource_name: resource.ref, resource_module: resource.resource}
    )
  end
end
