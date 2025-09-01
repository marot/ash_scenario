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
            key = {resource.resource, resource.name}
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
    resource_refs = Enum.map(resources, fn r -> {r.resource, r.name} end)
    run_resources(resource_refs, opts)
  end

  # Backward compatibility functions
  def run_scenario(resource_module, resource_name, opts \\ []), do: run_resource(resource_module, resource_name, opts)
  def run_scenarios(resource_refs, opts \\ []), do: run_resources(resource_refs, opts)
  def run_all_scenarios(resource_module, opts \\ []), do: run_all_resources(resource_module, opts)

  # Private Functions

  defp execute_resource(resource, opts, created_resources \\ %{}) do
    domain = Keyword.get(opts, :domain) || infer_domain(resource.resource)
    
    with {:ok, resolved_attributes} <- resolve_attributes(resource.attributes, created_resources),
         {:ok, create_action} <- get_create_action(resource.resource),
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

  defp resolve_attributes(attributes, created_resources) do
    resolved = 
      Enum.reduce_while(attributes, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
        case resolve_attribute_value(value, created_resources) do
          {:ok, resolved_value} -> 
            {:cont, {:ok, Map.put(acc, key, resolved_value)}}
          {:error, reason} -> 
            {:halt, {:error, reason}}
        end
      end)
    
    case resolved do
      {:ok, resolved_attrs} -> {:ok, resolved_attrs}
      error -> error
    end
  end

  defp resolve_attribute_value(value, created_resources) when is_atom(value) do
    # Check if this atom represents a reference to another resource
    # by looking in the created_resources map
    case find_referenced_resource(value, created_resources) do
      {:ok, resource} -> 
        # Return the resource's ID for relationship fields (blog_id, etc.)
        {:ok, resource.id}
      :not_found -> 
        # Not a resource reference, return the atom as-is
        {:ok, value}
    end
  end

  defp resolve_attribute_value(value, _created_resources), do: {:ok, value}

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
      %{resource: created_resource, resource_name: resource.name, resource_module: resource.resource}
    )
  end
end