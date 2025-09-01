defmodule AshScenario.Scenario.Runner do
  @moduledoc """
  Executes resources and creates Ash resources with dependency resolution.
  """

  alias AshScenario.Scenario.Registry

  @doc """
  Run a single resource by name from a resource.
  """
  def run_resource(resource_module, resource_name, opts \\ []) do
    case Registry.get_resource({resource_module, resource_name}) do
      nil -> 
        {:error, "Resource #{resource_name} not found in #{inspect(resource_module)}"}
      resource ->
        execute_resource(resource, opts)
    end
  end

  @doc """
  Run multiple resources with dependency resolution.
  """
  def run_resources(resource_refs, opts \\ []) when is_list(resource_refs) do
    with {:ok, ordered_resources} <- Registry.resolve_dependencies(resource_refs) do
      Enum.reduce_while(ordered_resources, {:ok, %{}}, fn resource, {:ok, created_resources} ->
        case execute_resource(resource, opts, created_resources) do
          {:ok, created_resource} -> 
            key = {resource.resource, resource.ref}
            {:cont, {:ok, Map.put(created_resources, key, created_resource)}}
          {:error, reason} -> 
            {:halt, {:error, reason}}
        end
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
    domain = Keyword.get(opts, :domain) || infer_domain(resource.resource)
    
    with {:ok, resolved_attributes} <- resolve_attributes(resource.attributes, resource.resource, created_resources) do
      if resource.function do
        # Use custom function
        case execute_custom_function(resource.function, resolved_attributes, opts) do
          {:ok, created_resource} ->
            track_created_resource(created_resource, resource)
            {:ok, created_resource}
          {:error, error} ->
            {:error, "Failed to create #{inspect(resource.resource)} with custom function: #{inspect(error)}"}
        end
      else
        # Use default Ash.create
        with {:ok, create_action} <- get_create_action(resource.resource),
             {:ok, changeset} <- build_changeset(resource.resource, create_action, resolved_attributes) do
          
          case Ash.create(changeset, domain: domain) do
            {:ok, created_resource} -> 
              track_created_resource(created_resource, resource)
              {:ok, created_resource}
            {:error, error} -> 
              {:error, "Failed to create #{inspect(resource.resource)}: #{inspect(error)}"}
          end
        end
      end
    end
  end

  defp resolve_attributes(attributes, resource_module, created_resources) do
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
      # Check if this atom represents a reference to another resource
      case find_referenced_resource(value, created_resources) do
        {:ok, resource} -> 
          # Return the resource's ID for relationship fields (blog_id, etc.)
          {:ok, resource.id}
        :not_found -> 
          # Not a resource reference, return the atom as-is
          {:ok, value}
      end
    else
      # Not a relationship attribute, keep the atom value as-is
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

  defp find_referenced_resource(resource_name, created_resources) do
    # Look for a resource created from a resource with the given name
    case Enum.find(created_resources, fn {{_resource, name}, _created} -> name == resource_name end) do
      {_key, resource} -> {:ok, resource}
      nil -> :not_found
    end
  end

  defp infer_domain(resource_module) do
    try do
      Ash.Resource.Info.domain(resource_module)
    rescue
      _ -> nil
    end
  end

  defp get_create_action(resource_module) do
    actions = Ash.Resource.Info.actions(resource_module)
    
    case Enum.find(actions, fn action -> action.type == :create end) do
      nil -> {:error, "No create action found for #{inspect(resource_module)}"}
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