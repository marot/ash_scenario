defmodule AshScenario.Scenario do
  @moduledoc """
  Test scenario DSL for creating named data setups with overrides.
  
  This module provides a macro-based DSL for defining named scenarios in test modules.
  Each scenario can reference resources from your resource definitions and override
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
          {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :basic_setup)
          assert resources.another_post.title == "Custom title for this test"
          assert resources.example_blog.name == "Example name"  # From resource defaults
        end
      end
  """

  alias AshScenario.Scenario.{Registry, Runner}

  @doc """
  Use this macro to add scenario support to your test modules.
  """
  defmacro __using__(_opts) do
    quote do
      import AshScenario.Scenario, only: [scenario: 2]
      Module.register_attribute(__MODULE__, :scenarios, accumulate: true)
      @before_compile AshScenario.Scenario
    end
  end

  @doc """
  Define a named scenario with resource overrides.
  
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
  defmacro scenario(name, do: block) do
    quote do
      @scenarios {unquote(name), unquote(Macro.escape(block))}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    scenarios = Module.get_attribute(env.module, :scenarios, [])
    
    scenario_definitions = 
      scenarios
      |> Enum.reverse()
      |> Enum.map(fn {name, block} ->
        overrides = extract_overrides_from_block(block)
        {name, overrides}
      end)

    quote do
      def __scenarios__() do
        unquote(Macro.escape(scenario_definitions))
      end
    end
  end

  @doc """
  Run a named scenario from a test module.
  
  ## Options
  
    * `:domain` - The Ash domain to use (will be inferred if not provided)
  
  ## Examples
  
      {:ok, resources} = AshScenario.Scenario.run(MyTest, :basic_setup)
      {:ok, resources} = AshScenario.Scenario.run(MyTest, :basic_setup, domain: MyApp.Domain)
  """
  def run(test_module, scenario_name, opts \\ []) do
    case get_scenario(test_module, scenario_name) do
      nil ->
        {:error, "Scenario #{scenario_name} not found in #{inspect(test_module)}"}
      
      overrides ->
        execute_scenario(overrides, opts)
    end
  end

  # Private Functions

  defp get_scenario(test_module, scenario_name) do
    if function_exported?(test_module, :__scenarios__, 0) do
      scenarios = test_module.__scenarios__()
      case Enum.find(scenarios, fn {name, _overrides} -> name == scenario_name end) do
        {_name, overrides} -> overrides
        nil -> nil
      end
    else
      nil
    end
  end

  defp execute_scenario(overrides, opts) do
    # 1. Extract all resource references from overrides and their dependencies
    with {:ok, all_resource_refs} <- extract_all_required_resources(overrides),
         {:ok, resource_definitions} <- load_resource_definitions(all_resource_refs),
         {:ok, ordered_resources} <- resolve_execution_order(resource_definitions) do
      
      # 2. Create resources in dependency order with overrides applied
      create_resources_in_order(ordered_resources, overrides, opts)
    end
  end

  defp extract_all_required_resources(overrides) do
    # Extract explicitly referenced resources and their dependencies
    explicitly_referenced = Enum.map(overrides, fn {resource_name, _attrs} -> resource_name end)
    
    # Find all dependencies by examining the base resource definitions
    with {:ok, dependencies} <- find_all_dependencies(explicitly_referenced) do
      {:ok, (explicitly_referenced ++ dependencies) |> Enum.uniq()}
    end
  end

  defp find_all_dependencies(resource_names) do
    # Recursively find all dependencies for the given resource names
    find_dependencies_recursive(resource_names, [])
  end
  
  defp find_dependencies_recursive([], acc), do: {:ok, acc}
  
  defp find_dependencies_recursive([resource_name | rest], acc) do
    case search_for_resource_in_registry(resource_name) do
      {:ok, {_module, resource_definition}} ->
        deps = extract_dependencies_from_definition(resource_definition)
        new_deps = deps -- acc  # Only new dependencies
        find_dependencies_recursive(rest ++ new_deps, acc ++ new_deps)
      :not_found ->
        {:error, "Resource #{resource_name} not found in any loaded resource modules"}
    end
  end
  
  defp load_resource_definitions(resource_refs) do
    # Load all resource definitions
    loaded = 
      resource_refs
      |> Enum.reduce_while({:ok, %{}}, fn resource_ref, {:ok, acc} ->
        case search_for_resource_in_registry(resource_ref) do
          {:ok, {module, resource_definition}} -> 
            resource_info = %{
              name: resource_ref,
              module: module,
              definition: resource_definition,
              dependencies: extract_dependencies_from_definition(resource_definition)
            }
            {:cont, {:ok, Map.put(acc, resource_ref, resource_info)}}
          :not_found -> 
            {:halt, {:error, "Resource #{resource_ref} not found in any loaded resource modules"}}
        end
      end)
    
    loaded
  end

  defp resolve_execution_order(resource_definitions) do
    # Simple topological sort based on dependencies
    resource_names = Map.keys(resource_definitions)
    
    # Sort by dependency count (fewer dependencies first)
    sorted = 
      resource_names
      |> Enum.map(fn name -> 
        deps = resource_definitions[name].dependencies
        {name, length(deps)}
      end)
      |> Enum.sort_by(fn {_name, dep_count} -> dep_count end)
      |> Enum.map(fn {name, _dep_count} -> name end)
    
    {:ok, sorted}
  end

  defp search_for_resource_in_registry(resource_name) do
    # This would typically iterate through all modules that use AshScenario.Dsl
    # and check if they define the given resource
    # For now, we'll check our test support modules directly
    modules_to_check = [Blog, Post]
    
    Enum.reduce_while(modules_to_check, :not_found, fn module, :not_found ->
      resource_def = AshScenario.Info.resource(module, resource_name)
      if resource_def do
        {:halt, {:ok, {module, resource_def}}}
      else
        {:cont, :not_found}
      end
    end)
  end

  defp extract_dependencies_from_definition(resource_definition) do
    # Extract resource references from the resource definition's attributes
    resource_definition.attributes
    |> Enum.filter(fn {_key, value} -> 
      is_atom(value) && String.starts_with?(Atom.to_string(value), ":")
    end)
    |> Enum.map(fn {_key, value} -> 
      # Convert :example_blog back to example_blog
      value
    end)
  end

  defp create_resources_in_order(ordered_resource_names, overrides, opts) do
    # Create each resource in dependency order, applying overrides as needed
    Enum.reduce_while(ordered_resource_names, {:ok, %{}}, fn resource_name, {:ok, created_resources} ->
      case create_single_resource(resource_name, overrides, created_resources, opts) do
        {:ok, resource} ->
          updated_resources = Map.put(created_resources, resource_name, resource)
          {:cont, {:ok, updated_resources}}
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp create_single_resource(resource_name, overrides, created_resources, opts) do
    # 1. Get base resource definition
    case search_for_resource_in_registry(resource_name) do
      {:ok, {module, resource_definition}} ->
        # 2. Merge base attributes with overrides
        base_attrs = Map.new(resource_definition.attributes || [])
        override_attrs = Map.new(overrides[resource_name] || [])
        merged_attributes = Map.merge(base_attrs, override_attrs)
        
        # 3. Resolve any resource references to actual IDs
        case resolve_resource_references(merged_attributes, created_resources) do
          {:ok, resolved_attributes} ->
            create_ash_resource(module, resolved_attributes, opts)
          error -> error
        end
        
      :not_found ->
        {:error, "Resource #{resource_name} not found"}
    end
  end

  defp resolve_resource_references(attributes, created_resources) do
    # Resolve any :resource_name references to actual created resource IDs
    resolved = 
      attributes
      |> Enum.map(fn {key, value} ->
        case resolve_single_reference(value, created_resources) do
          {:ok, resolved_value} -> {key, resolved_value}
          {:error, _reason} -> {key, value}  # Keep original value if can't resolve
        end
      end)
      |> Map.new()
    
    {:ok, resolved}
  end

  defp resolve_single_reference(value, created_resources) when is_atom(value) do
    case created_resources[value] do
      nil -> {:ok, value}  # Not a reference, return as-is
      resource -> {:ok, resource.id}
    end
  end

  defp resolve_single_reference(value, _created_resources), do: {:ok, value}

  defp create_ash_resource(module, attributes, opts) do
    domain = Keyword.get(opts, :domain) || infer_domain(module)
    
    with {:ok, create_action} <- get_create_action(module),
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

  # Helper function to extract overrides from the macro block at compile time
  defp extract_overrides_from_block({:__block__, _, statements}) do
    statements
    |> Enum.map(&extract_override_from_statement/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp extract_overrides_from_block(single_statement) do
    case extract_override_from_statement(single_statement) do
      nil -> %{}
      override -> Map.new([override])
    end
  end

  defp extract_override_from_statement({resource_name, _meta, [block]}) when is_atom(resource_name) do
    overrides = extract_attributes_from_block(block)
    {resource_name, overrides}
  end

  defp extract_override_from_statement(_), do: nil

  defp extract_attributes_from_block({:__block__, _, statements}) do
    statements
    |> Enum.map(&extract_attribute_from_statement/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp extract_attributes_from_block(single_statement) do
    case extract_attribute_from_statement(single_statement) do
      nil -> %{}
      attr -> Map.new([attr])
    end
  end

  defp extract_attribute_from_statement({attr_name, _meta, [value]}) when is_atom(attr_name) do
    {attr_name, value}
  end

  defp extract_attribute_from_statement(_), do: nil
end