defmodule AshScenario.Scenario.Registry do
  @moduledoc """
  Registry for tracking resources across multiple resources and resolving
  cross-resource references.
  """

  use GenServer
  require Logger
  alias AshScenario.Log

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
    names = Enum.map(resources, & &1.ref)
    Log.debug(
      fn -> "register_resources module=#{inspect(resource_module)} names=#{inspect(names)}" end,
      component: :registry, resource: resource_module
    )
    GenServer.call(__MODULE__, {:register_resources, resource_module, resources})
  end

  @doc """
  Get a resource by reference (resource_module, resource_name).
  """
  def get_resource({resource_module, resource_name}) do
    Log.debug(
      fn -> "get_resource module=#{inspect(resource_module)} ref=#{resource_name}" end,
      component: :registry, resource: resource_module, ref: resource_name
    )
    GenServer.call(__MODULE__, {:get_resource, resource_module, resource_name})
  end

  @doc """
  Get all resources for a resource.
  """
  def get_resources(resource_module) do
    Log.debug(
      fn -> "get_resources module=#{inspect(resource_module)}" end,
      component: :registry, resource: resource_module
    )
    GenServer.call(__MODULE__, {:get_resources, resource_module})
  end

  @doc """
  Resolve resource dependencies and return execution order.
  """
  def resolve_dependencies(resources) when is_list(resources) do
    Log.debug(fn -> "resolve_dependencies input=#{inspect(resources)}" end, component: :registry)
    GenServer.call(__MODULE__, {:resolve_dependencies, resources})
  end

  @doc """
  Clear all registered resources (useful for tests).
  """
  def clear_all do
    Log.debug(fn -> "clear_all" end, component: :registry)
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
          dependencies: extract_dependencies(resource_module, resource.attributes)
        }
        
        acc
        |> Map.put_new(resource_module, %{})
        |> put_in([resource_module, resource.ref], resource_data)
      end)
    Log.info(
      fn -> "registered_resources module=#{inspect(resource_module)} count=#{length(resources)}" end,
      component: :registry, resource: resource_module
    )
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
    Log.debug(
      fn -> "resolved_order=#{Enum.map(ordered_resources, &{&1.resource, &1.ref}) |> inspect()}" end,
      component: :registry
    )
    {:reply, {:ok, ordered_resources}, state}
  end

  @impl true
  def handle_call(:clear_all, _from, _state) do
    {:reply, :ok, %{}}
  end

  # Private Functions

  defp extract_dependencies(resource_module, attributes) do
    attributes
    |> Enum.reduce([], fn {key, value}, acc ->
      if is_atom(value) do
        case related_module_for_attr(resource_module, key) do
          {:ok, related_module} -> [{related_module, value} | acc]
          :error -> acc
        end
      else
        acc
      end
    end)
    |> Enum.reverse()
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
    # Kahn's algorithm over the subgraph induced by the provided resources
    nodes = Enum.map(resources, fn r -> {r.resource, r.ref} end) |> MapSet.new()

    # Build reverse adjacency (dep -> [dependent]) and indegree as number of deps per node
    {reverse_edges, indegree} =
      Enum.reduce(resources, {%{}, %{}}, fn r, {rev, indeg} ->
        node = {r.resource, r.ref}
        deps_in_graph = Enum.filter(r.dependencies, &MapSet.member?(nodes, &1))

        indeg = Map.put(indeg, node, length(deps_in_graph))

        rev =
          Enum.reduce(deps_in_graph, rev, fn dep, acc ->
            Map.update(acc, dep, [node], &[node | &1])
          end)

        {rev, indeg}
      end)

    Log.debug(
      fn -> "toposort indegree=#{inspect(indegree)} rev_edges=#{inspect(reverse_edges)}" end,
      component: :registry
    )

    queue =
      indegree
      |> Enum.filter(fn {_node, deg} -> deg == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> :queue.from_list()

    {order, remaining_indegree} = process_queue(queue, reverse_edges, indegree, [])

    if Enum.any?(remaining_indegree, fn {_n, deg} -> deg > 0 end) do
      Log.error(fn -> "dependency_cycle_detected indegree=#{inspect(remaining_indegree)}" end, component: :registry)
      {:error, "Cycle detected in resource dependencies"}
    else
      # Return resources in topological order
      ordered_resources =
        order
        |> Enum.map(fn {mod, ref} -> Enum.find(resources, fn r -> r.resource == mod and r.ref == ref end) end)

      {:ok, ordered_resources}
    end
  end

  defp process_queue(queue, reverse_edges, indegree, order) do
    case :queue.out(queue) do
      {{:value, node}, queue} ->
        order = [node | order]
        {queue, indegree} =
          Enum.reduce(Map.get(reverse_edges, node, []), {queue, indegree}, fn dependent, {q, degs} ->
            new_deg = (degs[dependent] || 0) - 1
            degs = Map.put(degs, dependent, new_deg)
            if new_deg == 0 do
              {:queue.in(dependent, q), degs}
            else
              {q, degs}
            end
          end)

        process_queue(queue, reverse_edges, indegree, order)

      {:empty, _queue} ->
        {Enum.reverse(order), indegree}
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
end
