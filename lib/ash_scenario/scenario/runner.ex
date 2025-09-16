defmodule AshScenario.Scenario.Runner do
  @moduledoc """
  Executes resources and creates Ash resources with dependency resolution.
  """

  alias AshScenario.Scenario.Executor

  @strategy AshScenario.Scenario.Executor.DatabaseStrategy

  @doc """
  Run a single prototype by name from an Ash resource module.

  Note: This function automatically resolves and creates all dependencies.
  """
  def run_prototype(resource_module, prototype_name, opts \\ []) do
    Executor.execute_single_prototype(resource_module, prototype_name, opts, @strategy)
  end

  @doc """
  Run multiple prototypes with dependency resolution.
  """
  def run_prototypes(prototype_refs, opts \\ []) when is_list(prototype_refs) do
    Executor.execute_prototypes(prototype_refs, opts, @strategy)
  end

  @doc """
  Run all prototypes defined for a resource module.
  """
  def run_all_prototypes(resource_module, opts \\ []) do
    Executor.execute_all_prototypes(resource_module, opts, @strategy)
  end
end
