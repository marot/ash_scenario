defmodule AshScenario.Examples.Domain do
  @moduledoc """
  Ash domain bundling the resources used in the example test scenarios.
  """

  use Ash.Domain

  resources do
    resource(AshScenario.Examples.Organization)
    resource(AshScenario.Examples.Project)
    resource(AshScenario.Examples.Member)
    resource(AshScenario.Examples.Task)
    resource(AshScenario.Examples.ChecklistItem)
  end
end
