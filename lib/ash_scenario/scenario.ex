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

  @doc """
  Use this macro to add scenario support to your test modules.
  """
  defmacro __using__(_opts) do
    quote do
      import AshScenario.Scenario, only: [scenario: 2, scenario: 3]
      Module.register_attribute(__MODULE__, :scenarios, accumulate: true)
      @before_compile AshScenario.Scenario
    end
  end

  @doc """
  Define a named scenario with prototype overrides.

  ## Examples

      scenario :my_test_data do
        example_post do
          title "Override title"
          content "Override content"
        end

        tech_blog do
          name "Custom blog name"
        end
      end
  """
  defmacro scenario(name, opts \\ [], do: block) do
    base_scenario = Keyword.get(opts, :extends)

    quote do
      @scenarios {unquote(name), unquote(Macro.escape(block)), unquote(base_scenario)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    scenarios = Module.get_attribute(env.module, :scenarios, [])

    scenario_definitions =
      scenarios
      |> Enum.reverse()
      |> Enum.map(fn scenario_data ->
        case scenario_data do
          {name, block, base_scenario} ->
            overrides = extract_overrides_from_ast(block)
            resolved_overrides = merge_with_base_scenario(overrides, base_scenario, scenarios)
            {name, resolved_overrides}

          {name, block} ->
            # Backward compatibility for scenarios without extends
            overrides = extract_overrides_from_ast(block)
            {name, overrides}
        end
      end)

    quote do
      def __scenarios__() do
        unquote(Macro.escape(scenario_definitions))
      end
    end
  end

  # Compile-time version of extract_overrides_from_block for macro expansion
  defp extract_overrides_from_ast({:__block__, _, statements}) do
    statements
    |> Enum.map(&extract_override_from_ast/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp extract_overrides_from_ast(single_statement) do
    case extract_override_from_ast(single_statement) do
      nil -> %{}
      override -> Map.new([override])
    end
  end

  defp extract_override_from_ast({proto_name, _meta, [[do: block]]}) when is_atom(proto_name) do
    overrides = extract_attributes_from_ast(block)
    {proto_name, overrides}
  end

  defp extract_override_from_ast({proto_name, _meta, [block]}) when is_atom(proto_name) do
    overrides = extract_attributes_from_ast(block)
    {proto_name, overrides}
  end

  defp extract_override_from_ast(_), do: nil

  defp extract_attributes_from_ast({:__block__, _, statements}) do
    statements
    |> Enum.map(&extract_attribute_from_ast/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp extract_attributes_from_ast(single_statement) do
    case extract_attribute_from_ast(single_statement) do
      nil -> %{}
      attr -> Map.new([attr])
    end
  end

  defp extract_attribute_from_ast({attr_name, _meta, [value]}) when is_atom(attr_name) do
    {attr_name, value}
  end

  # Handle do-block syntax: attr_name(do: block) becomes attr_name: value
  defp extract_attribute_from_ast({attr_name, _meta, [[do: value]]}) when is_atom(attr_name) do
    {attr_name, value}
  end

  defp extract_attribute_from_ast(_), do: nil

  # Scenario merging logic for extension support
  defp merge_with_base_scenario(overrides, nil, _all_scenarios), do: overrides

  defp merge_with_base_scenario(overrides, base_scenario_name, all_scenarios) do
    case find_base_scenario(base_scenario_name, all_scenarios) do
      nil ->
        # Base scenario not found, return original overrides
        # In practice, this could be an error, but we'll be lenient
        overrides

      base_overrides ->
        deep_merge_scenarios(base_overrides, overrides)
    end
  end

  defp find_base_scenario(base_name, all_scenarios) do
    case Enum.find(all_scenarios, fn scenario_data ->
           case scenario_data do
             {^base_name, _block} -> true
             {^base_name, _block, _base} -> true
             _ -> false
           end
         end) do
      nil ->
        nil

      {_name, block} ->
        extract_overrides_from_ast(block)

      {_name, block, base} ->
        # Recursively resolve base scenarios
        base_overrides = extract_overrides_from_ast(block)
        merge_with_base_scenario(base_overrides, base, all_scenarios)
    end
  end

  defp deep_merge_scenarios(base, extension) do
    Map.merge(base, extension, fn _prototype_name, base_attrs, ext_attrs ->
      # Merge attributes for the same prototype - extension overrides base
      Map.merge(base_attrs, ext_attrs)
    end)
  end

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

  # Private Functions

  defp get_scenario_with_validation(test_module, scenario_name) do
    cond do
      not function_exported?(test_module, :__scenarios__, 0) ->
        {:error,
         "Module #{inspect(test_module)} does not define any scenarios. Did you forget to add `use AshScenario.Scenario`?"}

      true ->
        scenarios = test_module.__scenarios__()

        case Enum.find(scenarios, fn {name, _overrides} -> name == scenario_name end) do
          {_name, overrides} ->
            {:ok, overrides}

          nil ->
            available_scenarios =
              scenarios |> Enum.map(fn {name, _} -> name end) |> Enum.join(", ")

            {:error,
             "Scenario #{scenario_name} not found in #{inspect(test_module)}. Available scenarios: #{available_scenarios}"}
        end
    end
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

  defp search_for_prototype_in_registry(prototype_name) do
    # Dynamic discovery of modules that use AshScenario.Dsl
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
    try do
      # Check if the module has prototypes defined (which means it uses our DSL)
      AshScenario.Info.has_prototypes?(module)
    rescue
      _ -> false
    end
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
              create_ash_resource(module, resolved_attributes, opts, create_cfg.action || :create)
            end

          error ->
            error
        end

      :not_found ->
        # Ensure atom names are displayed with a leading ':' for consistency
        {:error, "Prototype #{inspect(prototype_name)} not found"}
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
    if is_relationship_attribute?(module, attr_name) do
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
    {:error,
     "Invalid custom function. Must be {module, function, args} or a 2-arity function, got: #{inspect(fun)}"}
  end

  defp create_ash_resource(module, attributes, opts, preferred_action) do
    domain = Keyword.get(opts, :domain) || infer_domain(module)

    with {:ok, create_action} <- get_create_action(module, preferred_action),
         {:ok, changeset} <- build_changeset(module, create_action, attributes) do
      case Ash.create(changeset, domain: domain) do
        {:ok, resource} -> {:ok, resource}
        {:error, error} -> {:error, "Failed to create #{inspect(module)}: #{inspect(error)}"}
      end
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
end
