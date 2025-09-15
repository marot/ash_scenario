defmodule AshScenarioExamples.TestHelpers do
  @moduledoc false

  alias Ash.DataLayer.Ets
  alias AshScenario.Examples.{ChecklistItem, Member, Organization, Project, Task}

  @resources [Organization, Project, Member, Task, ChecklistItem]

  def reset_examples do
    Enum.each(@resources, &Ets.stop(&1))
    :ok
  end

  def domain, do: AshScenario.Examples.Domain
end
