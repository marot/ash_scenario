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
  @spec run(module(), atom(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(test_module, scenario_name, opts \\ []) do
    with {:ok, overrides} <- get_scenario_with_validation(test_module, scenario_name),
         {:ok, _} <- validate_prototypes_exist(overrides, test_module) do
      execute_scenario(overrides, opts, test_module)
    end
  end

  @doc """
  Create structs for a named scenario from a test module without database persistence.

  This is useful for generating test data for stories or other use cases
  where you need the data structure but don't want to persist to the database.

  ## Examples

      {:ok, structs} = AshScenario.Scenario.create_structs(MyTest, :basic_setup)
  """
  @spec create_structs(module(), atom(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def create_structs(test_module, scenario_name, opts \\ []) do
    with {:ok, overrides} <- get_scenario_with_validation(test_module, scenario_name),
         {:ok, _} <- validate_prototypes_exist(overrides, test_module) do
      execute_scenario_structs(overrides, opts, test_module)
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

  @spec validate_prototypes_exist(map(), module()) :: {:ok, :valid} | {:error, String.t()}
  defp validate_prototypes_exist(overrides, test_module) do
    # Check that all referenced prototypes actually exist
    missing_prototypes =
      overrides
      |> Map.keys()
      |> Enum.filter(fn ref_or_name ->
        result =
          case ref_or_name do
            {module, name} when is_atom(module) and is_atom(name) ->
              # Module-scoped reference
              search_for_prototype_in_registry({module, name})

            name when is_atom(name) ->
              # Simple name - use test_module context if available
              search_for_prototype_in_registry(name, test_module)

            _ ->
              :not_found
          end

        case result do
          {:ok, _} -> false
          :not_found -> true
        end
      end)

    if missing_prototypes == [] do
      {:ok, :valid}
    else
      formatted_missing =
        Enum.map(missing_prototypes, fn
          {module, name} -> "#{inspect(module)}.#{name}"
          name -> to_string(name)
        end)

      {:error,
       "Unknown prototypes referenced in scenario: #{Enum.join(formatted_missing, ", ")}. Make sure these prototypes are defined in your Ash resource modules."}
    end
  end

  @spec execute_scenario(map(), keyword(), module()) :: {:ok, map()} | {:error, String.t()}
  defp execute_scenario(overrides, opts, test_module) do
    # Convert both prototype refs and overrides to the format Runner expects
    {runner_refs, runner_overrides} =
      Enum.reduce(overrides, {[], %{}}, fn {ref_or_name, attrs}, {refs, ovr} ->
        # Handle both atom names and {module, name} tuples
        normalized_ref =
          case ref_or_name do
            {module, name} when is_atom(module) and is_atom(name) ->
              # Already a module-scoped reference
              {module, name}

            name when is_atom(name) ->
              # Simple name - find the module with test context
              case search_for_prototype_in_registry(name, test_module) do
                {:ok, {module, _def}} ->
                  {module, name}

                _ ->
                  nil
              end

            _ ->
              nil
          end

        if normalized_ref do
          {[normalized_ref | refs], Map.put(ovr, normalized_ref, attrs)}
        else
          {refs, ovr}
        end
      end)

    runner_refs = Enum.reverse(runner_refs)

    # Call the Runner with the converted prototype refs and overrides
    opts_with_overrides = Keyword.put(opts, :overrides, runner_overrides)

    case AshScenario.Scenario.Runner.run_prototypes(runner_refs, opts_with_overrides) do
      {:ok, resources} ->
        # Convert from {module, atom} keys to atom keys for simpler access
        converted =
          Enum.reduce(resources, %{}, fn {{_module, name}, resource}, acc ->
            Map.put(acc, name, resource)
          end)

        {:ok, converted}

      error ->
        error
    end
  end

  @spec execute_scenario_structs(map(), keyword(), module()) ::
          {:ok, map()} | {:error, String.t()}
  defp execute_scenario_structs(overrides, opts, _test_module) do
    # Convert overrides map to the format StructBuilder expects
    {runner_refs, runner_overrides} =
      Enum.reduce(overrides, {[], %{}}, fn {ref_or_name, attrs}, {refs, ovr} ->
        # Handle both atom names and {module, name} tuples
        normalized_ref =
          case ref_or_name do
            {module, name} when is_atom(module) and is_atom(name) ->
              # Already a module-scoped reference
              {module, name}

            name when is_atom(name) ->
              # Simple name - shouldn't happen in scenario context
              nil

            _ ->
              nil
          end

        if normalized_ref do
          {[normalized_ref | refs], Map.put(ovr, normalized_ref, attrs)}
        else
          {refs, ovr}
        end
      end)

    runner_refs = Enum.reverse(runner_refs)

    # Use StructBuilder which properly uses Registry for dependency resolution
    opts_with_overrides = Keyword.put(opts, :overrides, runner_overrides)

    case AshScenario.Scenario.StructBuilder.run_prototypes_structs(
           runner_refs,
           opts_with_overrides
         ) do
      {:ok, structs} ->
        # Convert from {module, atom} keys to atom keys for simpler access
        converted =
          Enum.reduce(structs, %{}, fn {{_module, name}, resource}, acc ->
            Map.put(acc, name, resource)
          end)

        {:ok, converted}

      error ->
        error
    end
  end

  # Helper functions for searching prototypes in registry

  @type prototype_ref :: {module(), atom()}
  @type created_resources_map :: %{prototype_ref() => struct()}

  @spec search_for_prototype_in_registry(atom() | {module(), atom()}, module() | nil) ::
          {:ok, {module(), map()}} | :not_found
  defp search_for_prototype_in_registry(prototype_ref, test_module \\ nil)

  defp search_for_prototype_in_registry({module, prototype_name}, _test_module)
       when is_atom(module) do
    # Module-scoped reference - always use registry (triggers auto-registration)
    case AshScenario.Scenario.Registry.get_prototype({module, prototype_name}) do
      nil ->
        :not_found

      _prototype_data ->
        # Get the full definition from the module for compatibility
        resource_def = AshScenario.Info.prototype(module, prototype_name)

        if resource_def do
          {:ok, {module, resource_def}}
        else
          :not_found
        end
    end
  end

  defp search_for_prototype_in_registry(prototype_name, test_module)
       when is_atom(prototype_name) do
    # Simple prototype name - prioritize test module namespace if provided
    modules = discover_resource_modules()

    # If test_module provided, sort to prioritize its namespace
    sorted_modules =
      if test_module do
        test_prefix = Module.split(test_module) |> Enum.take(2) |> Module.concat()

        Enum.sort_by(modules, fn mod ->
          # Prioritize modules under the test module's namespace
          if String.starts_with?(inspect(mod), inspect(test_prefix)) do
            0
          else
            1
          end
        end)
      else
        modules
      end

    case sorted_modules do
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
end
