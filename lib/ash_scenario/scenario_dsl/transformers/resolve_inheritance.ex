defmodule AshScenario.ScenarioDsl.Transformers.ResolveInheritance do
  @moduledoc """
  Resolves scenario inheritance by merging extended scenarios with their base scenarios.

  This transformer handles the `extends` option in scenarios, allowing scenarios to
  inherit and override prototypes from other scenarios defined in the same module.
  """
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(_), do: [AshScenario.ScenarioDsl.Transformers.ValidatePrototypes]

  def transform(dsl_state) do
    scenarios = Transformer.get_entities(dsl_state, [:scenarios])

    # Build dependency graph
    case build_inheritance_graph(scenarios) do
      {:ok, graph} ->
        # Resolve inheritance for each scenario
        resolved_scenarios = resolve_all_scenarios(scenarios, graph)

        # Persist resolved data for runtime access
        dsl_state = Transformer.persist(dsl_state, :resolved_scenarios, resolved_scenarios)
        {:ok, dsl_state}

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_inheritance_graph(scenarios) do
    # Build a map of scenario names to their definitions
    scenario_map = Map.new(scenarios, &{&1.name, &1})

    # Check for circular dependencies and missing parents
    Enum.reduce_while(scenarios, {:ok, scenario_map}, fn scenario, {:ok, map} ->
      case validate_inheritance(scenario, map) do
        :ok -> {:cont, {:ok, map}}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_inheritance(scenario, scenario_map) do
    case scenario.extends do
      nil ->
        :ok

      parent when is_atom(parent) ->
        if Map.has_key?(scenario_map, parent) do
          check_circular_dependency(scenario.name, parent, scenario_map)
        else
          {:error,
           Spark.Error.DslError.exception(
             message: "Scenario '#{scenario.name}' extends unknown scenario '#{parent}'",
             path: [:scenarios, scenario.name]
           )}
        end

      parents when is_list(parents) ->
        Enum.reduce_while(parents, :ok, fn parent, :ok ->
          if Map.has_key?(scenario_map, parent) do
            case check_circular_dependency(scenario.name, parent, scenario_map) do
              :ok -> {:cont, :ok}
              error -> {:halt, error}
            end
          else
            {:halt,
             {:error,
              Spark.Error.DslError.exception(
                message: "Scenario '#{scenario.name}' extends unknown scenario '#{parent}'",
                path: [:scenarios, scenario.name]
              )}}
          end
        end)
    end
  end

  defp check_circular_dependency(child, parent, scenario_map, visited \\ MapSet.new()) do
    cond do
      child == parent ->
        {:error,
         Spark.Error.DslError.exception(
           message: "Circular dependency detected: scenario '#{child}' cannot extend itself",
           path: [:scenarios, child]
         )}

      MapSet.member?(visited, parent) ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "Circular dependency detected in scenario inheritance chain involving '#{child}' and '#{parent}'",
           path: [:scenarios, child]
         )}

      true ->
        visited = MapSet.put(visited, parent)
        parent_scenario = Map.get(scenario_map, parent)

        case parent_scenario.extends do
          nil ->
            :ok

          grandparent when is_atom(grandparent) ->
            check_circular_dependency(child, grandparent, scenario_map, visited)

          grandparents when is_list(grandparents) ->
            Enum.reduce_while(grandparents, :ok, fn gp, :ok ->
              case check_circular_dependency(child, gp, scenario_map, visited) do
                :ok -> {:cont, :ok}
                error -> {:halt, error}
              end
            end)
        end
    end
  end

  defp resolve_all_scenarios(scenarios, graph) do
    # Resolve inheritance and merge prototype overrides
    Map.new(scenarios, fn scenario ->
      resolved = resolve_scenario(scenario, graph, MapSet.new())
      {scenario.name, resolved}
    end)
  end

  defp resolve_scenario(scenario, graph, visited) do
    if MapSet.member?(visited, scenario.name) do
      raise Spark.Error.DslError.exception(
              message: "Circular dependency detected for scenario '#{scenario.name}'",
              path: [:scenarios, scenario.name]
            )
    end

    visited = MapSet.put(visited, scenario.name)

    case scenario.extends do
      nil ->
        scenario

      parent when is_atom(parent) ->
        parent_scenario = Map.get(graph, parent)
        resolved_parent = resolve_scenario(parent_scenario, graph, visited)
        merge_scenarios(resolved_parent, scenario)

      parents when is_list(parents) ->
        # Merge multiple parents left-to-right
        Enum.reduce(parents, scenario, fn parent, acc ->
          parent_scenario = Map.get(graph, parent)
          resolved_parent = resolve_scenario(parent_scenario, graph, visited)
          merge_scenarios(resolved_parent, acc)
        end)
    end
  end

  defp merge_scenarios(parent, child) do
    # Merge prototype overrides, with child taking precedence
    merged_prototypes = merge_prototypes(parent.prototypes || [], child.prototypes || [])

    %{child | prototypes: merged_prototypes}
  end

  defp merge_prototypes(parent_prototypes, child_prototypes) do
    # Create a map of child prototypes for quick lookup
    child_map = Map.new(child_prototypes, &{&1.ref, &1})

    # Merge: child overrides take precedence
    merged =
      Enum.map(parent_prototypes, fn parent_proto ->
        case Map.get(child_map, parent_proto.ref) do
          nil -> parent_proto
          child_proto -> merge_prototype_override(parent_proto, child_proto)
        end
      end)

    # Add any child prototypes not in parent
    child_only =
      Enum.filter(child_prototypes, fn child_proto ->
        not Enum.any?(parent_prototypes, &(&1.ref == child_proto.ref))
      end)

    merged ++ child_only
  end

  defp merge_prototype_override(parent, child) do
    # Merge attributes, with child taking precedence
    merged_attrs = merge_attributes(parent.attributes || [], child.attributes || [])
    %{child | attributes: merged_attrs}
  end

  defp merge_attributes(parent_attrs, child_attrs) do
    # Create a map of child attributes for quick lookup
    child_map = Map.new(child_attrs, &{&1.name, &1})

    # Merge: child attributes take precedence
    merged =
      Enum.map(parent_attrs, fn parent_attr ->
        Map.get(child_map, parent_attr.name, parent_attr)
      end)

    # Add any child attributes not in parent
    child_only =
      Enum.filter(child_attrs, fn child_attr ->
        not Enum.any?(parent_attrs, &(&1.name == child_attr.name))
      end)

    merged ++ child_only
  end
end
