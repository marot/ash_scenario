defmodule AshScenario.ScenarioInfoTest do
  use ExUnit.Case
  use AshScenario.Scenario

  scenario :test_scenario do
    prototype :example_post do
      attr(:title, "Test Post")
    end
  end

  scenario :another_scenario do
    prototype :example_blog do
      attr(:name, "Test Blog")
    end
  end

  scenario :inherited_scenario do
    extends(:test_scenario)

    prototype :example_post do
      attr(:title, "Inherited Post Title")
    end
  end

  describe "scenarios/1" do
    test "returns all scenarios defined in the module" do
      scenarios = AshScenario.ScenarioInfo.scenarios(__MODULE__)

      assert is_list(scenarios)
      assert length(scenarios) == 3

      scenario_names = Enum.map(scenarios, & &1.name)
      assert :test_scenario in scenario_names
      assert :another_scenario in scenario_names
      assert :inherited_scenario in scenario_names
    end
  end

  describe "scenario/2" do
    test "returns a specific scenario by name" do
      scenario = AshScenario.ScenarioInfo.scenario(__MODULE__, :test_scenario)

      assert scenario != nil
      assert scenario.name == :test_scenario
      assert length(scenario.prototypes) == 1

      prototype = List.first(scenario.prototypes)
      assert prototype.ref == :example_post
    end

    test "returns nil for non-existent scenario" do
      scenario = AshScenario.ScenarioInfo.scenario(__MODULE__, :non_existent)
      assert scenario == nil
    end
  end
end
