defmodule AshScenario.ModuleAttributeErrorTest do
  use ExUnit.Case

  test "using undefined module attribute keeps the AST node" do
    # This test verifies that when a module attribute is not defined,
    # the expansion keeps the original AST node (doesn't crash)

    defmodule TestModuleWithUndefinedAttribute do
      use AshScenario.Scenario

      # Note: @undefined_attr is NOT defined

      scenario :with_undefined do
        example_blog do
          # This should remain as AST
          name @undefined_attr
        end
      end

      # Define scenarios to access them
      def test_scenarios, do: __scenarios__()
    end

    # Get the scenarios
    scenarios = TestModuleWithUndefinedAttribute.test_scenarios()

    # Find the :with_undefined scenario
    {_name, overrides} = Enum.find(scenarios, fn {name, _} -> name == :with_undefined end)

    # The undefined attribute should remain as an AST node
    # (not expanded to a value)
    name_value = overrides[:example_blog][:name]

    # Verify it's still an AST tuple (not expanded)
    assert is_tuple(name_value)
    assert elem(name_value, 0) == :@
  end
end
