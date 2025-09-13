defmodule AshScenario.ScenarioInfo do
  @moduledoc """
  Runtime introspection for scenarios defined with Spark DSL.
  """

  @doc """
  Get all scenarios defined in a module.
  """
  def scenarios(module) do
    Spark.Dsl.Extension.get_entities(module, [:scenarios])
  end

  @doc """
  Get a specific scenario by name.
  """
  def scenario(module, name) do
    module
    |> scenarios()
    |> Enum.find(&(&1.name == name))
  end

  @doc """
  Get resolved scenario with inheritance applied.
  """
  def resolved_scenario(module, name) do
    case Spark.Dsl.Extension.get_persisted(module, :resolved_scenarios) do
      nil -> scenario(module, name)
      resolved -> Map.get(resolved, name)
    end
  end
end
