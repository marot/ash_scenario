defmodule AshScenario.Scenario do
  @moduledoc """
  Test scenario DSL for creating named data setups with overrides.

  This module provides a macro-based DSL for defining named scenarios in test modules.
  Each scenario can reference prototypes from your prototype definitions and override
  specific attributes while maintaining automatic dependency resolution.

  ## Usage

      defmodule MyTest do
        use ExUnit.Case
        use AshScenario.Scenario

        scenario :basic_setup do
          another_post do
            title "Custom title for this test"
          end
        end

        scenario :with_multiple_posts do
          example_post do
            title "First post"
          end
          another_post do
            title "Second post"
          end
        end

        test "basic scenario" do
          {:ok, instances} = AshScenario.Scenario.run(__MODULE__, :basic_setup)
          assert instances.another_post.title == "Custom title for this test"
          assert instances.example_blog.name == "Example name"  # From prototype defaults
        end
      end
  """

  use Spark.Dsl,
    default_extensions: [
      extensions: [AshScenario.ScenarioDsl]
    ]

  @doc """
  Run a named scenario from a test module.

  ## Options

    * `:domain` - The Ash domain to use (will be inferred if not provided)

  ## Examples

      {:ok, instances} = AshScenario.Scenario.run(MyTest, :basic_setup)
      {:ok, instances} = AshScenario.Scenario.run(MyTest, :basic_setup, domain: MyApp.Domain)
  """
  def run(test_module, scenario_name, opts \\ []) do
    with {:ok, overrides} <- get_scenario_with_validation(test_module, scenario_name),
         {:ok, _} <- validate_prototypes_exist(overrides) do
      execute_scenario(overrides, opts)
    end
  end

  @doc """
  Create structs for a named scenario from a test module without database persistence.

  This is useful for generating test data for stories or other use cases
  where you need the data structure but don't want to persist to the database.

  ## Examples

      {:ok, structs} = AshScenario.Scenario.create_structs(MyTest, :basic_setup)
  """
  def create_structs(test_module, scenario_name, opts \\ []) do
    with {:ok, overrides} <- get_scenario_with_validation(test_module, scenario_name),
         {:ok, _} <- validate_prototypes_exist(overrides) do
      execute_scenario_structs(overrides, opts)
    end
  end

  # Private Functions

  defp get_scenario_with_validation(test_module, scenario_name) do
    if function_exported?(test_module, :spark_dsl_config, 0) do
      case AshScenario.ScenarioInfo.resolved_scenario(test_module, scenario_name) do
        nil ->
          available_scenarios =
            AshScenario.ScenarioInfo.scenarios(test_module)
            |> Enum.map_join(", ", & &1.name)

          if available_scenarios == "" do
            {:error,
             "Module #{inspect(test_module)} does not define any scenarios. Did you forget to add `use AshScenario.Scenario`?"}
          else
            {:error,
             "Scenario #{scenario_name} not found in #{inspect(test_module)}. Available scenarios: #{available_scenarios}"}
          end

        scenario ->
          # Convert Spark DSL format to override map format
          overrides = convert_scenario_to_overrides(scenario)
          {:ok, overrides}
      end
    else
      {:error,
       "Module #{inspect(test_module)} does not define any scenarios. Did you forget to add `use AshScenario.Scenario`?"}
    end
  end

  # Convert Spark DSL scenario format to override map format
  defp convert_scenario_to_overrides(scenario) do
    (scenario.prototypes || [])
    |> Enum.reduce(%{}, fn prototype_override, acc ->
      attrs_map =
        (prototype_override.attributes || [])
        |> Enum.map(fn attr -> {attr.name, attr.value} end)
        |> Map.new()

      Map.put(acc, prototype_override.ref, attrs_map)
    end)
  end

  defp validate_prototypes_exist(overrides) do
    # Check that all referenced prototypes actually exist
    missing_prototypes =
      overrides
      |> Map.keys()
      |> Enum.filter(fn prototype_name ->
        case search_for_prototype_in_registry(prototype_name) do
          {:ok, _} -> false
          :not_found -> true
        end
      end)

    if missing_prototypes == [] do
      {:ok, :valid}
    else
      {:error,
       "Unknown prototypes referenced in scenario: #{Enum.join(missing_prototypes, ", ")}. Make sure these prototypes are defined in your Ash resource modules."}
    end
  end

  defp execute_scenario(overrides, opts) do
    # Convert both prototype refs and overrides to the format Runner expects
    {runner_refs, runner_overrides} =
      Enum.reduce(overrides, {[], %{}}, fn {name, attrs}, {refs, ovr} ->
        # Find the module for this prototype
        case search_for_prototype_in_registry(name) do
          {:ok, {module, _def}} ->
            ref = {module, name}
            {[ref | refs], Map.put(ovr, ref, attrs)}

          _ ->
            {refs, ovr}
        end
      end)

    runner_refs = Enum.reverse(runner_refs)

    # Call the Runner with the converted prototype refs and overrides
    opts_with_overrides = Keyword.put(opts, :overrides, runner_overrides)

    case AshScenario.Scenario.Runner.run_prototypes(runner_refs, opts_with_overrides) do
      {:ok, resources} ->
        # Convert back from {module, atom} keys to atom keys for backward compatibility
        converted =
          Enum.reduce(resources, %{}, fn {{_module, name}, resource}, acc ->
            Map.put(acc, name, resource)
          end)

        {:ok, converted}

      error ->
        error
    end
  end

  defp execute_scenario_structs(overrides, opts) do
    # 1. Extract explicitly referenced prototypes
    explicitly_referenced = Map.keys(overrides)

    # 2. Find all dependencies and build complete prototype list
    with {:ok, all_proto_names} <-
           find_all_dependencies_for_overrides(explicitly_referenced, %{}),
         {:ok, ordered_prototypes} <- resolve_dependency_order(all_proto_names) do
      # 3. Create prototypes as structs in dependency order with overrides applied
      create_prototype_structs_in_order(ordered_prototypes, overrides, opts)
    end
  end

  # TODO: The functions below are only used by execute_scenario_structs
  # which should also be refactored to use a common path once
  # the Runner supports struct creation

  @spec find_all_dependencies_for_overrides([atom()], map()) :: {:ok, [prototype_ref()]}
  defp find_all_dependencies_for_overrides(prototype_names, resource_map) do
    # Normalize all names to {module, atom} format first
    normalized_names =
      Enum.map(prototype_names, fn name ->
        case search_for_prototype_in_registry(name) do
          {:ok, {module, _}} -> {module, name}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Recursively build prototype map with dependencies
    case build_complete_prototype_map(normalized_names, resource_map, MapSet.new()) do
      {:ok, complete_map} ->
        all_refs = Map.keys(complete_map)
        {:ok, all_refs}

      error ->
        error
    end
  end

  @spec build_complete_prototype_map([prototype_ref()], map(), MapSet.t()) ::
          {:ok, map()} | {:error, String.t()}
  defp build_complete_prototype_map([], resource_map, _visited), do: {:ok, resource_map}

  defp build_complete_prototype_map([{module, _name} = ref | rest], resource_map, visited) do
    if MapSet.member?(visited, ref) do
      # Skip if already processed
      build_complete_prototype_map(rest, resource_map, visited)
    else
      case search_for_prototype_in_registry(ref) do
        {:ok, {_module, prototype_definition}} ->
          deps = extract_direct_dependencies(prototype_definition, module)
          # Normalize dependencies to {module, atom} format
          normalized_deps =
            Enum.map(deps, fn dep_name ->
              case search_for_prototype_in_registry(dep_name) do
                {:ok, {dep_module, _}} -> {dep_module, dep_name}
                _ -> nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          proto_info = %{
            module: module,
            definition: prototype_definition,
            dependencies: normalized_deps
          }

          new_proto_map = Map.put(resource_map, ref, proto_info)
          new_visited = MapSet.put(visited, ref)

          # Add dependencies to the list to process
          build_complete_prototype_map(rest ++ normalized_deps, new_proto_map, new_visited)

        :not_found ->
          {:error,
           "Prototype #{inspect(ref)} not found in any loaded resource modules. Available prototypes: #{list_available_prototypes()}"}
      end
    end
  end

  @type prototype_ref :: {module(), atom()}
  @type created_resources_map :: %{prototype_ref() => struct()}

  @spec resolve_dependency_order([prototype_ref()]) :: {:ok, [prototype_ref()]}
  defp resolve_dependency_order(prototype_refs) do
    # Build dependency graph
    dep_graph =
      prototype_refs
      |> Enum.map(fn {module, _name} = ref ->
        case search_for_prototype_in_registry(ref) do
          {:ok, {_mod, prototype_definition}} ->
            deps = extract_direct_dependencies(prototype_definition, module)
            # Normalize dependencies to {module, atom} format
            normalized_deps =
              Enum.map(deps, fn dep_name ->
                case search_for_prototype_in_registry(dep_name) do
                  {:ok, {dep_module, _}} -> {dep_module, dep_name}
                  _ -> nil
                end
              end)
              |> Enum.reject(&is_nil/1)

            {ref, normalized_deps}

          :not_found ->
            {ref, []}
        end
      end)
      |> Map.new()

    # Proper topological sort using Kahn's algorithm
    sorted = topological_sort(dep_graph)
    {:ok, sorted}
  end

  defp topological_sort(dep_graph) do
    # Build reverse dependency map (who depends on each node)
    reverse_deps =
      Enum.reduce(dep_graph, %{}, fn {node, deps}, acc ->
        acc = Map.put_new(acc, node, MapSet.new())

        Enum.reduce(deps, acc, fn dep, acc2 ->
          Map.update(acc2, dep, MapSet.new([node]), &MapSet.put(&1, node))
        end)
      end)

    # Find nodes with no dependencies
    no_deps =
      dep_graph
      |> Enum.filter(fn {_node, deps} -> Enum.empty?(deps) end)
      |> Enum.map(fn {node, _} -> node end)

    do_topological_sort(no_deps, dep_graph, reverse_deps, [])
  end

  defp do_topological_sort([], _dep_graph, _reverse_deps, sorted), do: Enum.reverse(sorted)

  defp do_topological_sort([node | rest], dep_graph, reverse_deps, sorted) do
    # Add node to sorted list
    new_sorted = [node | sorted]

    # Find nodes that depended on this node
    dependents = Map.get(reverse_deps, node, MapSet.new())

    # Remove this node from their dependencies and add to queue if they have no more deps
    {new_queue, new_dep_graph} =
      Enum.reduce(dependents, {rest, dep_graph}, fn dependent, {queue, graph} ->
        remaining_deps =
          Map.get(graph, dependent, [])
          |> Enum.reject(&(&1 == node))

        new_graph = Map.put(graph, dependent, remaining_deps)

        if Enum.empty?(remaining_deps) do
          {[dependent | queue], new_graph}
        else
          {queue, new_graph}
        end
      end)

    do_topological_sort(new_queue, new_dep_graph, reverse_deps, new_sorted)
  end

  defp extract_direct_dependencies(prototype_definition, module) do
    # Only treat atoms on relationship source attributes as dependencies
    relationships =
      try do
        Ash.Resource.Info.relationships(module)
      rescue
        _ -> []
      end

    relationship_source_attributes = MapSet.new(Enum.map(relationships, & &1.source_attribute))

    deps =
      prototype_definition.attributes
      |> Enum.reduce([], fn {key, value}, acc ->
        if MapSet.member?(relationship_source_attributes, key) and is_atom(value) do
          [value | acc]
        else
          acc
        end
      end)

    deps
    |> Enum.reverse()
  end

  defp search_for_prototype_in_registry({module, prototype_name}) when is_atom(module) do
    # Module-scoped reference - search only in the specified module
    if module_uses_ash_scenario_dsl?(module) do
      resource_def = AshScenario.Info.prototype(module, prototype_name)

      if resource_def do
        {:ok, {module, resource_def}}
      else
        :not_found
      end
    else
      :not_found
    end
  end

  defp search_for_prototype_in_registry(prototype_name) when is_atom(prototype_name) do
    # Simple prototype name - search across all modules (existing behavior)
    case discover_resource_modules() do
      [] ->
        :not_found

      modules ->
        Enum.reduce_while(modules, :not_found, fn module, :not_found ->
          resource_def = AshScenario.Info.prototype(module, prototype_name)

          if resource_def do
            {:halt, {:ok, {module, resource_def}}}
          else
            {:cont, :not_found}
          end
        end)
    end
  end

  defp discover_resource_modules do
    # Get all loaded modules and filter for those using AshScenario.Dsl
    :code.all_loaded()
    |> Enum.map(fn {module, _path} -> module end)
    |> Enum.filter(&module_uses_ash_scenario_dsl?/1)
  end

  defp module_uses_ash_scenario_dsl?(module) do
    # Check if the module has prototypes defined (which means it uses our DSL)
    AshScenario.Info.has_prototypes?(module)
  rescue
    _ -> false
  end

  defp list_available_prototypes do
    discover_resource_modules()
    |> Enum.flat_map(fn module ->
      try do
        AshScenario.Info.prototype_names(module)
        |> Enum.map(fn name -> "#{name} (in #{module})" end)
      rescue
        _ -> []
      end
    end)
    |> Enum.join(", ")
  end

  @spec create_prototype_structs_in_order([prototype_ref()], map(), keyword()) ::
          {:ok, map()} | {:error, any()}
  defp create_prototype_structs_in_order(ordered_prototype_refs, overrides, opts) do
    # Create each prototype struct in dependency order, applying overrides as needed
    Enum.reduce_while(ordered_prototype_refs, {:ok, %{}}, fn {_module, _name} = ref,
                                                             {:ok, created_structs} ->
      case create_single_prototype_struct(ref, overrides, created_structs, opts) do
        {:ok, scoped_key, struct} ->
          # Always store with the scoped key for consistency
          updated_structs = Map.put(created_structs, scoped_key, struct)
          {:cont, {:ok, updated_structs}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @spec create_single_prototype_struct(prototype_ref(), map(), map(), keyword()) ::
          {:ok, prototype_ref(), struct()} | {:error, any()}
  defp create_single_prototype_struct({module, name} = ref, overrides, created_structs, opts) do
    # 1. Get base prototype definition
    case search_for_prototype_in_registry(ref) do
      {:ok, {_module, prototype_definition}} ->
        # 2. Merge base attributes with overrides
        base_attrs = Map.new(prototype_definition.attributes || [])
        # Overrides might be keyed by atom only or by {module, atom}
        override_attrs = Map.new(overrides[ref] || overrides[name] || [])
        merged_attributes = Map.merge(base_attrs, override_attrs)

        # 3. Resolve any prototype references to structs (not IDs)
        {:ok, resolved_attributes} =
          resolve_prototype_struct_references(merged_attributes, module, created_structs)

        # 4. Use module-level create configuration (custom function or action)
        create_cfg = AshScenario.Info.create(module)

        result =
          if create_cfg.function do
            execute_custom_function(create_cfg.function, resolved_attributes, opts)
          else
            # Create struct without database persistence
            create_struct(module, resolved_attributes, opts)
          end

        # Add the ref to the result
        case result do
          {:ok, struct} -> {:ok, ref, struct}
          error -> error
        end

      :not_found ->
        {:error, "Prototype #{inspect(ref)} not found"}
    end
  end

  defp resolve_prototype_struct_references(attributes, module, created_structs) do
    # Resolve any :prototype_name references to actual structs (not IDs)
    resolved =
      attributes
      |> Enum.map(fn {key, value} ->
        {:ok, resolved_value} =
          resolve_single_struct_reference(value, key, module, created_structs)

        {key, resolved_value}
      end)
      |> Map.new()

    {:ok, resolved}
  end

  defp resolve_single_struct_reference(value, attr_name, module, created_structs)
       when is_atom(value) do
    # Only resolve atoms that correspond to relationship attributes
    if relationship_attribute?(module, attr_name) do
      # Always look for scoped key first since we store everything scoped
      # Need to find the right module for this prototype
      matching_struct =
        Enum.find_value(created_structs, fn
          {{_mod, ^value}, struct} -> struct
          _ -> nil
        end)

      case matching_struct do
        # Not a reference, return as-is
        nil -> {:ok, value}
        # Return the struct itself
        struct -> {:ok, struct}
      end
    else
      # Not a relationship attribute, keep the atom value as-is
      {:ok, value}
    end
  end

  defp resolve_single_struct_reference(value, _attr_name, _module, _created_structs),
    do: {:ok, value}

  defp create_struct(module, attributes, _opts) do
    # Get primary key field(s)
    primary_key = Ash.Resource.Info.primary_key(module)

    # Generate ID if needed and not provided
    attributes_with_id =
      case {primary_key, Map.has_key?(attributes, :id)} do
        {[:id], false} ->
          Map.put(attributes, :id, Ash.UUID.generate())

        _ ->
          attributes
      end

    # Add timestamps if the resource has them and they're not provided
    now = DateTime.utc_now()

    attributes_with_timestamps =
      attributes_with_id
      |> maybe_add_timestamp(:inserted_at, now, module)
      |> maybe_add_timestamp(:updated_at, now, module)

    # Create the struct
    struct = struct(module, attributes_with_timestamps)

    {:ok, struct}
  rescue
    error ->
      {:error, "Failed to build struct: #{inspect(error)}"}
  end

  defp maybe_add_timestamp(attributes, field, default_value, resource_module) do
    if Map.has_key?(attributes, field) do
      attributes
    else
      # Check if the resource has this timestamp field
      case Ash.Resource.Info.attribute(resource_module, field) do
        nil -> attributes
        _attr -> Map.put(attributes, field, default_value)
      end
    end
  end

  defp relationship_attribute?(resource_module, attr_name) do
    resource_module
    |> Ash.Resource.Info.relationships()
    |> Enum.any?(fn rel ->
      rel.source_attribute == attr_name
    end)
  rescue
    _ -> false
  end

  defp execute_custom_function({module, function, extra_args}, resolved_attributes, opts) do
    apply(module, function, [resolved_attributes, opts] ++ extra_args)
  rescue
    error -> {:error, "Custom function failed: #{inspect(error)}"}
  end

  defp execute_custom_function(fun, resolved_attributes, opts) when is_function(fun, 2) do
    fun.(resolved_attributes, opts)
  rescue
    error -> {:error, "Custom function failed: #{inspect(error)}"}
  end

  defp execute_custom_function(fun, _resolved_attributes, _opts) do
    {:error,
     "Invalid custom function. Must be {module, function, args} or a 2-arity function, got: #{inspect(fun)}"}
  end
end
