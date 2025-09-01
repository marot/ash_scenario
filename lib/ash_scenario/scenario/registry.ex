defmodule AshScenario.Scenario.Registry do
  @moduledoc """
  Registry for tracking resources across multiple resources and resolving
  cross-resource references.
  """

  use GenServer

  @type resource_ref :: {module(), atom()}
  @type resource_data :: %{
    ref: atom(),
    resource: module(),
    attributes: map(),
    dependencies: [resource_ref()]
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts ++ [name: __MODULE__])
  end

  @doc """
  Register resources from a resource module.
  """
  def register_resources(resource_module) do
    resources = AshScenario.Info.resources(resource_module)
    GenServer.call(__MODULE__, {:register_resources, resource_module, resources})
  end

  @doc """
  Get a resource by reference (resource_module, resource_name).
  """
  def get_resource({resource_module, resource_name}) do
    GenServer.call(__MODULE__, {:get_resource, resource_module, resource_name})
  end

  @doc """
  Get all resources for a resource.
  """
  def get_resources(resource_module) do
    GenServer.call(__MODULE__, {:get_resources, resource_module})
  end

  @doc """
  Resolve resource dependencies and return execution order.
  """
  def resolve_dependencies(resources) when is_list(resources) do
    GenServer.call(__MODULE__, {:resolve_dependencies, resources})
  end

  @doc """
  Clear all registered resources (useful for tests).
  """
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  # Backward compatibility functions
  def register_scenarios(resource_module), do: register_resources(resource_module)
  def get_scenario(ref), do: get_resource(ref)
  def get_scenarios(resource_module), do: get_resources(resource_module)

  # GenServer Callbacks

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register_resources, resource_module, resources}, _from, state) do
    updated_state = 
      resources
      |> Enum.reduce(state, fn resource, acc ->
        resource_data = %{
          ref: resource.ref,
          resource: resource_module,
          attributes: resource.attributes,
          dependencies: extract_dependencies(resource.attributes)
        }
        
        acc
        |> Map.put_new(resource_module, %{})
        |> put_in([resource_module, resource.ref], resource_data)
      end)

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:get_resource, resource_module, resource_name}, _from, state) do
    resource = get_in(state, [resource_module, resource_name])
    {:reply, resource, state}
  end

  @impl true
  def handle_call({:get_resources, resource_module}, _from, state) do
    resources = Map.get(state, resource_module, %{}) |> Map.values()
    {:reply, resources, state}
  end

  @impl true
  def handle_call({:resolve_dependencies, resource_refs}, _from, state) do
    {:ok, ordered_resources} = build_dependency_graph(resource_refs, state)
    {:reply, {:ok, ordered_resources}, state}
  end

  @impl true
  def handle_call(:clear_all, _from, _state) do
    {:reply, :ok, %{}}
  end

  # Private Functions

  defp extract_dependencies(attributes) do
    attributes
    |> Enum.filter(fn {_key, value} -> is_atom(value) && String.starts_with?(Atom.to_string(value), ":") end)
    |> Enum.map(fn {_key, resource_name} -> 
      # For now, we assume cross-resource references need to be resolved at runtime
      # This is a simplified implementation - in practice, you'd need more sophisticated
      # dependency resolution that can find resources across different resources
      {:unknown_resource, resource_name}
    end)
  end

  defp build_dependency_graph(resource_refs, state) do
    resources = 
      resource_refs
      |> Enum.map(fn {resource, ref} -> get_in(state, [resource, ref]) end)
      |> Enum.reject(&is_nil/1)

    # Simple topological sort - this is a basic implementation
    # In practice, you'd want more robust cycle detection and ordering
    {:ok, sorted} = topological_sort(resources)
    {:ok, sorted}
  end

  defp topological_sort(resources) do
    # Simplified topological sort implementation
    # This just returns resources in reverse dependency order for now
    resources_with_deps = 
      resources
      |> Enum.map(fn resource ->
        dep_count = length(resource.dependencies)
        {resource, dep_count}
      end)
      |> Enum.sort_by(fn {_resource, dep_count} -> dep_count end)
      |> Enum.map(fn {resource, _dep_count} -> resource end)

    {:ok, resources_with_deps}
  end
end