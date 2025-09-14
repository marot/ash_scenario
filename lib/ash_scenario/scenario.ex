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
    # 1. Extract explicitly referenced prototypes
    explicitly_referenced = Map.keys(overrides)

    # 2. Find all dependencies and build complete prototype list
    with {:ok, all_proto_names} <-
           find_all_dependencies_for_overrides(explicitly_referenced, %{}),
         {:ok, ordered_prototypes} <- resolve_dependency_order(all_proto_names) do
      # 3. Create prototypes in dependency order with overrides applied
      create_prototypes_in_order(ordered_prototypes, overrides, opts)
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

  defp find_all_dependencies_for_overrides(prototype_names, resource_map) do
    # Recursively build prototype map with dependencies
    case build_complete_prototype_map(prototype_names, resource_map, MapSet.new()) do
      {:ok, complete_map} ->
        all_names = Map.keys(complete_map)
        {:ok, all_names}

      error ->
        error
    end
  end

  defp build_complete_prototype_map([], resource_map, _visited), do: {:ok, resource_map}

  defp build_complete_prototype_map([prototype_name | rest], resource_map, visited) do
    if MapSet.member?(visited, prototype_name) do
      # Skip if already processed
      build_complete_prototype_map(rest, resource_map, visited)
    else
      case search_for_prototype_in_registry(prototype_name) do
        {:ok, {module, prototype_definition}} ->
          deps = extract_direct_dependencies(prototype_definition, module)
          proto_info = %{module: module, definition: prototype_definition, dependencies: deps}

          new_proto_map = Map.put(resource_map, prototype_name, proto_info)
          new_visited = MapSet.put(visited, prototype_name)

          # Add dependencies to the list to process
          build_complete_prototype_map(rest ++ deps, new_proto_map, new_visited)

        :not_found ->
          {:error,
           "Prototype #{inspect(prototype_name)} not found in any loaded resource modules. Available prototypes: #{list_available_prototypes()}"}
      end
    end
  end

  defp resolve_dependency_order(prototype_names) do
    # Simple topological sort by dependency count
    sorted =
      prototype_names
      |> Enum.map(fn name ->
        case search_for_prototype_in_registry(name) do
          {:ok, {mod, prototype_definition}} ->
            deps = extract_direct_dependencies(prototype_definition, mod)
            {name, length(deps)}

          :not_found ->
            {name, 0}
        end
      end)
      |> Enum.sort_by(fn {_name, dep_count} -> dep_count end)
      |> Enum.map(fn {name, _dep_count} -> name end)

    {:ok, sorted}
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

    prototype_definition.attributes
    |> Enum.reduce([], fn {key, value}, acc ->
      if MapSet.member?(relationship_source_attributes, key) and is_atom(value) do
        [value | acc]
      else
        acc
      end
    end)
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

  defp create_prototypes_in_order(ordered_prototype_names, overrides, opts) do
    # Create each prototype in dependency order, applying overrides as needed
    Enum.reduce_while(ordered_prototype_names, {:ok, %{}}, fn prototype_name,
                                                              {:ok, created_resources} ->
      case create_single_prototype(prototype_name, overrides, created_resources, opts) do
        {:ok, resource} ->
          updated_resources = Map.put(created_resources, prototype_name, resource)
          {:cont, {:ok, updated_resources}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp create_prototype_structs_in_order(ordered_prototype_names, overrides, opts) do
    # Create each prototype struct in dependency order, applying overrides as needed
    Enum.reduce_while(ordered_prototype_names, {:ok, %{}}, fn prototype_name,
                                                              {:ok, created_structs} ->
      case create_single_prototype_struct(prototype_name, overrides, created_structs, opts) do
        {:ok, scoped_key, struct} ->
          # Always store with the scoped key for consistency
          updated_structs = Map.put(created_structs, scoped_key, struct)
          {:cont, {:ok, updated_structs}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp create_single_prototype_struct(prototype_name, overrides, created_structs, opts) do
    # 1. Get base prototype definition
    case search_for_prototype_in_registry(prototype_name) do
      {:ok, {module, prototype_definition}} ->
        # 2. Determine the canonical scoped key for storage
        # Always use {module, name} format for consistency
        scoped_key =
          case prototype_name do
            # Already scoped, use the found module
            {_mod, name} -> {module, name}
            # Unscoped, add module
            name when is_atom(name) -> {module, name}
          end

        # 3. Merge base attributes with overrides
        base_attrs = Map.new(prototype_definition.attributes || [])
        override_attrs = Map.new(overrides[prototype_name] || [])
        merged_attributes = Map.merge(base_attrs, override_attrs)

        # 3. Resolve any prototype references to structs (not IDs)
        case resolve_prototype_struct_references(merged_attributes, module, created_structs) do
          {:ok, resolved_attributes} ->
            # 4. Use module-level create configuration (custom function or action)
            create_cfg = AshScenario.Info.create(module)

            result =
              if create_cfg.function do
                execute_custom_function(create_cfg.function, resolved_attributes, opts)
              else
                # Create struct without database persistence
                create_struct(module, resolved_attributes, opts)
              end

            # Add the scoped_key to the result
            case result do
              {:ok, struct} -> {:ok, scoped_key, struct}
              error -> error
            end

          error ->
            error
        end

      :not_found ->
        {:error, "Prototype #{inspect(prototype_name)} not found"}
    end
  end

  defp create_single_prototype(prototype_name, overrides, created_resources, opts) do
    # 1. Get base prototype definition
    case search_for_prototype_in_registry(prototype_name) do
      {:ok, {module, prototype_definition}} ->
        # 2. Merge base attributes with overrides
        base_attrs = Map.new(prototype_definition.attributes || [])
        override_attrs = Map.new(overrides[prototype_name] || [])
        merged_attributes = Map.merge(base_attrs, override_attrs)

        # 3. Resolve any prototype references to actual IDs
        case resolve_prototype_references(merged_attributes, module, created_resources) do
          {:ok, resolved_attributes} ->
            # 4. Use module-level create configuration (custom function or action)
            create_cfg = AshScenario.Info.create(module)

            if create_cfg.function do
              execute_custom_function(create_cfg.function, resolved_attributes, opts)
            else
              create_ash_resource(
                module,
                resolved_attributes,
                opts,
                create_cfg.action || :create
              )
            end

          error ->
            error
        end

      :not_found ->
        # Ensure atom names are displayed with a leading ':' for consistency
        {:error, "Prototype #{inspect(prototype_name)} not found"}
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

  defp resolve_prototype_references(attributes, module, created_prototypes) do
    # Resolve any :prototype_name references to actual created record IDs
    resolved =
      attributes
      |> Enum.map(fn {key, value} ->
        {:ok, resolved_value} = resolve_single_reference(value, key, module, created_prototypes)
        {key, resolved_value}
      end)
      |> Map.new()

    {:ok, resolved}
  end

  defp resolve_single_reference(value, attr_name, module, created_prototypes)
       when is_atom(value) do
    # Only resolve atoms that correspond to relationship attributes
    if relationship_attribute?(module, attr_name) do
      case created_prototypes[value] do
        # Not a reference, return as-is
        nil -> {:ok, value}
        prototype -> {:ok, prototype.id}
      end
    else
      # Not a relationship attribute, keep the atom value as-is
      {:ok, value}
    end
  end

  defp resolve_single_reference(value, _attr_name, _module, _created_prototypes), do: {:ok, value}

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

  defp create_ash_resource(module, attributes, opts, preferred_action) do
    domain = Keyword.get(opts, :domain) || infer_domain(module)

    with {:ok, create_action} <- get_create_action(module, preferred_action),
         {:ok, changeset} <- build_changeset(module, create_action, attributes, opts) do
      case Ash.create(changeset, domain: domain) do
        {:ok, resource} -> {:ok, resource}
        {:error, error} -> {:error, "Failed to create #{inspect(module)}: #{inspect(error)}"}
      end
    end
  end

  defp infer_domain(resource_module) do
    Ash.Resource.Info.domain(resource_module)
  rescue
    _ -> nil
  end

  defp get_create_action(resource_module, preferred_action) do
    actions = Ash.Resource.Info.actions(resource_module)

    case Enum.find(actions, fn action ->
           action.type == :create and action.name == preferred_action
         end) do
      nil ->
        case Enum.find(actions, fn action -> action.type == :create end) do
          nil -> {:error, "No create action found for #{inspect(resource_module)}"}
          action -> {:ok, action.name}
        end

      action ->
        {:ok, action.name}
    end
  end

  defp build_changeset(resource_module, action_name, attributes, _opts) do
    # Drop nil values
    sanitized_attributes =
      attributes
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    require Logger

    Logger.debug(
      "[scenario] build_changeset resource=#{inspect(resource_module)} action=#{inspect(action_name)} attrs_in=#{inspect(attributes)} sanitized=#{inspect(sanitized_attributes)}"
    )

    changeset =
      resource_module
      |> Ash.Changeset.for_create(action_name, sanitized_attributes)

    require Logger

    Logger.debug(
      "[scenario] built_changeset resource=#{inspect(resource_module)} action=#{inspect(action_name)} changes=#{inspect(Map.get(changeset, :changes, %{}))}"
    )

    {:ok, changeset}
  rescue
    error -> {:error, "Failed to build changeset: #{inspect(error)}"}
  end
end
