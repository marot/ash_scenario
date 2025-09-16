defmodule AshScenarioExamples.LaunchChecklistTest do
  use ExUnit.Case
  use AshScenario.Scenario

  alias Ash.Changeset
  alias AshScenarioExamples.TestHelpers

  setup tags do
    TestHelpers.reset_examples()

    AshScenario.register_prototypes(AshScenario.Examples.Organization)
    AshScenario.register_prototypes(AshScenario.Examples.ChecklistItem)
    AshScenario.register_prototypes(AshScenario.Examples.Member)
    AshScenario.register_prototypes(AshScenario.Examples.Project)
    AshScenario.register_prototypes(AshScenario.Examples.Task)

    {:ok, resources} = AshScenario.Scenario.run(__MODULE__, tags[:scenario])

    {:ok, %{scenario: resources}}
  end

  describe "update/1" do
    scenario :go_live_checklist do
      # prototype :acme_corp do end
      prototype :review_copy do
      end
    end

    @tag scenario: :go_live_checklist
    test "review checklist items can be updated", %{
      scenario: %{
        :review_copy => review_item
      }
    } do
      {:ok, updated_review} =
        review_item
        |> Changeset.for_update(:update, %{completed: true})
        |> Ash.update(tenant: review_item.organization_id)

      assert updated_review.completed
    end
  end
end
