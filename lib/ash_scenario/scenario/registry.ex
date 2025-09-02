defmodule AshScenario.Scenario.Registry do
  @moduledoc """
  Registry for tracking prototypes across resource modules and resolving
  cross-prototype references.
  """

  use GenServer
  require Logger
  alias AshScenario.Log

  @type prototype_ref :: {module(), atom()}
  @type prototype_data :: %{
          ref: atom(),
          resource: module(),
          attributes: map(),
          dependencies: [prototype_ref()]
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts ++ [name: __MODULE__])
  end

  @doc """
  Register prototypes from a resource module.
  """
  def register_prototypes(resource_module) do
    prototypes = AshScenario.Info.prototypes(resource_module)
    names = Enum.map(prototypes, & &1.ref)

    Log.debug(
      fn -> "register_prototypes module=#{inspect(resource_module)} names=#{inspect(names)}" end,
      component: :registry,
      resource: resource_module
    )

    GenServer.call(__MODULE__, {:register_prototypes, resource_module, prototypes})
  end

  @doc """
  Get a prototype by reference (resource_module, prototype_name).
  """
  def get_prototype({resource_module, prototype_name}) do
    Log.debug(
      fn -> "get_prototype module=#{inspect(resource_module)} ref=#{prototype_name}" end,
      component: :registry,
      resource: resource_module,
      ref: prototype_name
    )

    GenServer.call(__MODULE__, {:get_prototype, resource_module, prototype_name})
  end

  @doc """
  Get all prototypes for a resource module.
  """
  def get_prototypes(resource_module) do
    Log.debug(
      fn -> "get_prototypes module=#{inspect(resource_module)}" end,
      component: :registry,
      resource: resource_module
    )

    GenServer.call(__MODULE__, {:get_prototypes, resource_module})
  end

  @doc """
  Resolve prototype dependencies and return execution order.
  """
  def resolve_dependencies(refs) when is_list(refs) do
    Log.debug(fn -> "resolve_dependencies input=#{inspect(refs)}" end, component: :registry)
    GenServer.call(__MODULE__, {:resolve_dependencies, refs})
  end

  @doc """
  Clear all registered prototypes (useful for tests).
  """
  def clear_all do
    Log.debug(fn -> "clear_all" end, component: :registry)
    GenServer.call(__MODULE__, :clear_all)
  end

  # Deprecated scenario-named functions removed. Use prototype-named API.

  # GenServer Callbacks

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register_prototypes, resource_module, prototypes}, _from, state) do
    updated_state =
      prototypes
      |> Enum.reduce(state, fn prototype, acc ->
        prototype_data = %{
          ref: prototype.ref,
          resource: resource_module,
          attributes: prototype.attributes,
          dependencies: extract_dependencies(resource_module, prototype.attributes),
          action: Map.get(prototype, :action),
          function: Map.get(prototype, :function)
        }

        acc
        |> Map.put_new(resource_module, %{})
        |> put_in([resource_module, prototype.ref], prototype_data)
      end)

    Log.info(
      fn ->
        "registered_prototypes module=#{inspect(resource_module)} count=#{length(prototypes)}"
      end,
      component: :registry,
      resource: resource_module
    )

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:get_prototype, resource_module, resource_name}, _from, state) do
    prototype = get_in(state, [resource_module, resource_name])
    {:reply, prototype, state}
  end

  @impl true
  def handle_call({:get_prototypes, resource_module}, _from, state) do
    prototypes = Map.get(state, resource_module, %{}) |> Map.values()
    {:reply, prototypes, state}
  end

  @impl true
  def handle_call({:resolve_dependencies, prototype_refs}, _from, state) do
    case build_dependency_graph(prototype_refs, state) do
      {:ok, ordered_prototypes} ->
        Log.debug(
          fn ->
            "resolved_order=#{Enum.map(ordered_prototypes, &{&1.resource, &1.ref}) |> inspect()}"
          end,
          component: :registry
        )

        {:reply, {:ok, ordered_prototypes}, state}

      {:error, reason} ->
        Log.error(
          fn -> "resolve_dependencies_error reason=#{inspect(reason)}" end,
          component: :registry
        )

        {:reply, {:error, reason}, state}
    end
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

  defp build_dependency_graph(prototype_refs, state) do
    # First, expand the prototype refs to include all transitive dependencies
    with {:ok, expanded_refs} <- expand_dependencies(prototype_refs, state) do
      prototypes =
        expanded_refs
        |> Enum.map(fn {resource, ref} -> get_in(state, [resource, ref]) end)
        |> Enum.reject(&is_nil/1)

      # Now do topological sort on the complete set
      {:ok, sorted} = topological_sort(prototypes)
      {:ok, sorted}
    end
  end

  defp expand_dependencies(prototype_refs, state) do
    expand_dependencies_recursive(prototype_refs, MapSet.new(), state)
  end

  defp expand_dependencies_recursive(prototype_refs, visited, state) do
    new_refs = Enum.reject(prototype_refs, &MapSet.member?(visited, &1))

    # Allow resolving a dependency by name across modules. If a dependency
    # references a different module (e.g., Blog) but the resource with that
    # name is defined under another module (e.g., CustomBlog), prefer the
    # declared module to satisfy ordering.
    new_refs = Enum.map(new_refs, &resolve_cross_module_ref(&1, state))

    if new_refs == [] do
      {:ok, MapSet.to_list(visited)}
    else
      # Validate that all new_refs actually exist after cross-module resolution
      case Enum.find(new_refs, fn {resource_module, ref} ->
             get_in(state, [resource_module, ref]) == nil
           end) do
        {missing_module, missing_ref} ->
          # Ensure atom refs render with a leading ':' for consistency
          {:error, "Prototype #{inspect(missing_ref)} not found in #{inspect(missing_module)}"}

        nil ->
          # All resources exist, proceed
          updated_visited = Enum.reduce(new_refs, visited, &MapSet.put(&2, &1))

          # Find dependencies for each new ref
          dependencies =
            new_refs
            |> Enum.flat_map(fn {resource_module, ref} ->
              resource_data = get_in(state, [resource_module, ref])
              resource_data.dependencies
            end)

          expand_dependencies_recursive(dependencies, updated_visited, state)
      end
    end
  end

  defp resolve_cross_module_ref({resource_module, ref} = tuple, state) do
    case get_in(state, [resource_module, ref]) do
      nil ->
        # Try to find any module that defines this ref
        case Enum.find(Map.keys(state), fn mod -> get_in(state, [mod, ref]) end) do
          nil -> tuple
          other_mod -> {other_mod, ref}
        end

      _ ->
        tuple
    end
  end

  defp topological_sort(prototypes) do
    # Kahn's algorithm over the subgraph induced by the provided resources
    nodes = Enum.map(prototypes, fn r -> {r.resource, r.ref} end) |> MapSet.new()

    # Build reverse adjacency (dep -> [dependent]) and indegree as number of deps per node
    {reverse_edges, indegree} =
      Enum.reduce(prototypes, {%{}, %{}}, fn r, {rev, indeg} ->
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
      Log.error(fn -> "dependency_cycle_detected indegree=#{inspect(remaining_indegree)}" end,
        component: :registry
      )

      {:error, "Cycle detected in prototype dependencies"}
    else
      # Return prototypes in topological order
      ordered_prototypes =
        order
        |> Enum.map(fn {mod, ref} ->
          Enum.find(prototypes, fn r -> r.resource == mod and r.ref == ref end)
        end)

      {:ok, ordered_prototypes}
    end
  end

  defp process_queue(queue, reverse_edges, indegree, order) do
    case :queue.out(queue) do
      {{:value, node}, queue} ->
        order = [node | order]

        {queue, indegree} =
          Enum.reduce(Map.get(reverse_edges, node, []), {queue, indegree}, fn dependent,
                                                                              {q, degs} ->
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
      case Enum.find(Ash.Resource.Info.relationships(resource_module), fn rel ->
             rel.source_attribute == attr_name
           end) do
        nil -> :error
        rel -> {:ok, rel.destination}
      end
    rescue
      _ -> :error
    end
  end
end
