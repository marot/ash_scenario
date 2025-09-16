defmodule AshScenario.Scenario.Registry do
  @moduledoc """
  Registry for tracking prototypes across resource modules and resolving
  cross-prototype references.
  """

  use GenServer
  require Logger

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
    GenServer.call(__MODULE__, {:register_prototypes, resource_module, prototypes})
  end

  @doc """
  Get a prototype by reference (resource_module, prototype_name).
  """
  def get_prototype({resource_module, prototype_name}) do
    GenServer.call(__MODULE__, {:get_prototype, resource_module, prototype_name})
  end

  @doc """
  Get all prototypes for a resource module.
  """
  def get_prototypes(resource_module) do
    GenServer.call(__MODULE__, {:get_prototypes, resource_module})
  end

  @doc """
  Resolve prototype dependencies and return execution order.
  """
  def resolve_dependencies(refs) when is_list(refs) do
    GenServer.call(__MODULE__, {:resolve_dependencies, refs})
  end

  @doc """
  Clear all registered prototypes (useful for tests).
  """
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  # Deprecated scenario-named functions removed. Use prototype-named API.

  # GenServer Callbacks

  @impl true
  def init(_) do
    # Auto-discover and register all prototypes from known domains
    state = discover_and_register_all_domains(%{})
    {:ok, state}
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

    # Check for circular dependencies after all prototypes are registered
    case detect_circular_dependencies(updated_state) do
      :ok ->
        {:reply, :ok, updated_state}

      {:error, cycle_info} ->
        # Don't update state if cycles detected
        {:reply, {:error, cycle_info}, state}
    end
  end

  @impl true
  def handle_call({:get_prototype, resource_module, resource_name}, _from, state) do
    {state, _registered?} = ensure_registered(resource_module, state)
    prototype = get_in(state, [resource_module, resource_name])
    {:reply, prototype, state}
  end

  @impl true
  def handle_call({:get_prototypes, resource_module}, _from, state) do
    {state, _registered?} = ensure_registered(resource_module, state)
    prototypes = Map.get(state, resource_module, %{}) |> Map.values()
    {:reply, prototypes, state}
  end

  @impl true
  def handle_call({:resolve_dependencies, prototype_refs}, _from, state) do
    # Lazily register any resource modules referenced in the request
    updated_state =
      prototype_refs
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.reduce(state, fn mod, acc ->
        {acc, _} = ensure_registered(mod, acc)
        acc
      end)

    case build_dependency_graph(prototype_refs, updated_state) do
      {:ok, ordered_prototypes, final_state} ->
        {:reply, {:ok, ordered_prototypes}, final_state}

      {:error, reason, final_state} ->
        {:reply, {:error, reason}, final_state}
    end
  end

  @impl true
  def handle_call(:clear_all, _from, _state) do
    {:reply, :ok, %{}}
  end

  # Private Functions

  # Auto-discover and register all prototypes from known domains
  defp discover_and_register_all_domains(state) do
    # For now, just return the state - we'll rely on lazy loading
    # Trying to auto-discover at startup is problematic because:
    # 1. We don't know which OTP app contains the user's domains
    # 2. Test modules aren't compiled yet at startup
    # 3. Users might have domains across multiple apps
    state
  end

  # Ensure a resource module's prototypes are present in the registry state.
  # Also registers all other resources in the same domain for dependency resolution.
  # Returns {updated_state, registered?}
  defp ensure_registered(resource_module, state) do
    if Map.has_key?(state, resource_module) do
      {state, false}
    else
      # Register this module first
      {state_with_module, _} = do_register_module(resource_module, state)

      # Try to register all resources in the same domain
      try do
        domain = Ash.Resource.Info.domain(resource_module)

        if domain do
          resources = Ash.Domain.Info.resources(domain)

          # Register all resources in the domain
          updated_state =
            Enum.reduce(resources, state_with_module, fn resource, acc ->
              if Map.has_key?(acc, resource) do
                acc
              else
                {new_state, _} = do_register_module(resource, acc)
                new_state
              end
            end)

          {updated_state, true}
        else
          {state_with_module, true}
        end
      rescue
        _ ->
          # If domain discovery fails, just return with the single module registered
          {state_with_module, true}
      end
    end
  end

  defp do_register_module(resource_module, state) do
    prototypes = AshScenario.Info.prototypes(resource_module)

    if prototypes == [] do
      {state, false}
    else
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

      {updated_state, true}
    end
  end

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
    case expand_dependencies(prototype_refs, state) do
      {:ok, expanded_refs, final_state} ->
        prototypes =
          expanded_refs
          |> Enum.map(fn {resource, ref} ->
            get_in(final_state, [resource, ref])
          end)
          |> Enum.reject(&is_nil/1)

        # Now do topological sort on the complete set
        # Cycles should be caught at compile time, so we can simplify this
        {:ok, sorted} = topological_sort(prototypes)
        {:ok, sorted, final_state}

      {:error, msg, final_state} ->
        {:error, msg, final_state}
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
      {:ok, MapSet.to_list(visited), state}
    else
      # Lazily register any modules missing at this point
      # Also register dependency modules discovered from attributes
      state_with_refs =
        new_refs
        |> Enum.map(&elem(&1, 0))
        |> Enum.uniq()
        |> Enum.reduce(state, fn mod, acc ->
          {new_acc, _} = ensure_registered(mod, acc)
          new_acc
        end)

      # Now also ensure dependency modules are registered
      dependency_modules =
        new_refs
        |> Enum.flat_map(fn {resource_module, ref} ->
          case get_in(state_with_refs, [resource_module, ref]) do
            nil ->
              []

            resource_data ->
              resource_data.dependencies
              |> Enum.map(&elem(&1, 0))
          end
        end)
        |> Enum.uniq()

      state_with_deps =
        Enum.reduce(dependency_modules, state_with_refs, fn mod, acc ->
          {new_acc, _} = ensure_registered(mod, acc)
          new_acc
        end)

      # Validate that all new_refs actually exist after cross-module resolution/registration
      case Enum.find(new_refs, fn {resource_module, ref} ->
             get_in(state_with_deps, [resource_module, ref]) == nil
           end) do
        {missing_module, missing_ref} ->
          {:error, "Prototype #{inspect(missing_ref)} not found in #{inspect(missing_module)}",
           state_with_deps}

        nil ->
          updated_visited = Enum.reduce(new_refs, visited, &MapSet.put(&2, &1))

          dependencies =
            new_refs
            |> Enum.flat_map(fn {resource_module, ref} ->
              resource_data = get_in(state_with_deps, [resource_module, ref])
              resource_data.dependencies
            end)

          expand_dependencies_recursive(dependencies, updated_visited, state_with_deps)
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

    queue =
      indegree
      |> Enum.filter(fn {_node, deg} -> deg == 0 end)
      |> Enum.map(&elem(&1, 0))
      |> :queue.from_list()

    {order, _remaining_indegree} = process_queue(queue, reverse_edges, indegree, [])

    # Return prototypes in topological order
    # Cycles are caught at compile time, so we don't check here
    ordered_prototypes =
      order
      |> Enum.map(fn {mod, ref} ->
        Enum.find(prototypes, fn r -> r.resource == mod and r.ref == ref end)
      end)

    {:ok, ordered_prototypes}
  end

  defp process_queue(queue, reverse_adjacency_list, indegrees, sorted_nodes) do
    case :queue.out(queue) do
      {{:value, current_node}, remaining_queue} ->
        updated_sorted = [current_node | sorted_nodes]

        {updated_queue, updated_indegrees} =
          Enum.reduce(
            Map.get(reverse_adjacency_list, current_node, []),
            {remaining_queue, indegrees},
            fn dependent_node, {queue_acc, indegree_map} ->
              new_indegree = (indegree_map[dependent_node] || 0) - 1
              updated_map = Map.put(indegree_map, dependent_node, new_indegree)

              if new_indegree == 0 do
                {:queue.in(dependent_node, queue_acc), updated_map}
              else
                {queue_acc, updated_map}
              end
            end
          )

        process_queue(updated_queue, reverse_adjacency_list, updated_indegrees, updated_sorted)

      {:empty, _queue} ->
        {Enum.reverse(sorted_nodes), indegrees}
    end
  end

  defp related_module_for_attr(resource_module, attr_name) do
    case Enum.find(Ash.Resource.Info.relationships(resource_module), fn rel ->
           rel.source_attribute == attr_name
         end) do
      nil -> :error
      rel -> {:ok, rel.destination}
    end
  rescue
    _ -> :error
  end

  # Detect circular dependencies across all registered prototypes
  defp detect_circular_dependencies(state) do
    # Build a flat dependency graph from all prototypes
    all_prototypes =
      state
      |> Enum.flat_map(fn {_module, prototypes} -> Map.values(prototypes) end)

    dependencies =
      all_prototypes
      |> Enum.reduce(%{}, fn prototype, acc ->
        Map.put(acc, {prototype.resource, prototype.ref}, prototype.dependencies || [])
      end)

    # Use DFS to detect cycles
    case detect_cycles(dependencies) do
      nil ->
        :ok

      cycle ->
        cycle_str =
          Enum.map_join(cycle, " -> ", fn {mod, ref} ->
            "#{inspect(mod)}.#{ref}"
          end)

        [{first_mod, first_ref} | _] = cycle

        error_msg = """
        Circular dependency detected in prototypes:

        #{cycle_str} -> #{inspect(first_mod)}.#{first_ref}

        Prototypes cannot have circular dependencies. Please restructure your prototypes to avoid cycles.
        """

        {:error, error_msg}
    end
  end

  defp detect_cycles(dependencies) do
    nodes = Map.keys(dependencies)
    detect_cycles_dfs(nodes, dependencies, MapSet.new(), MapSet.new(), [])
  end

  defp detect_cycles_dfs([], _dependencies, _visited, _rec_stack, _path) do
    nil
  end

  defp detect_cycles_dfs([node | rest], dependencies, visited, rec_stack, path) do
    if MapSet.member?(visited, node) do
      detect_cycles_dfs(rest, dependencies, visited, rec_stack, path)
    else
      case dfs_visit(node, dependencies, visited, MapSet.put(rec_stack, node), [node | path]) do
        {:cycle, cycle} ->
          cycle

        {new_visited, _new_rec} ->
          detect_cycles_dfs(rest, dependencies, new_visited, rec_stack, path)
      end
    end
  end

  defp dfs_visit(node, dependencies, visited, rec_stack, path) do
    deps = Map.get(dependencies, node, [])

    {visited, rec_stack, result} =
      Enum.reduce_while(deps, {MapSet.put(visited, node), rec_stack, nil}, fn dep,
                                                                              {vis, rec, _} ->
        cond do
          MapSet.member?(rec, dep) ->
            # Found a cycle - build the cycle path
            cycle_start_idx = Enum.find_index(path, &(&1 == dep))
            cycle = Enum.take(path, cycle_start_idx + 1) |> Enum.reverse()
            {:halt, {vis, rec, {:cycle, cycle}}}

          MapSet.member?(vis, dep) ->
            # Already visited in a different path, no cycle here
            {:cont, {vis, rec, nil}}

          true ->
            # Continue DFS
            case dfs_visit(dep, dependencies, vis, MapSet.put(rec, dep), [dep | path]) do
              {:cycle, cycle} ->
                {:halt, {vis, rec, {:cycle, cycle}}}

              {new_vis, new_rec} ->
                {:cont, {new_vis, new_rec, nil}}
            end
        end
      end)

    case result do
      {:cycle, cycle} -> {:cycle, cycle}
      nil -> {visited, MapSet.delete(rec_stack, node)}
    end
  end
end
