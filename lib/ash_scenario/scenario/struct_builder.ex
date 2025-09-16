defmodule AshScenario.Scenario.StructBuilder do
  @moduledoc """
  Builds structs from prototypes without database persistence.
  Used for generating test data for stories and other non-persistent use cases.
  """

  alias AshScenario.Scenario.Executor

  @strategy AshScenario.Scenario.Executor.StructStrategy

  @doc """
  Build a single prototype as a struct without persistence.
  """
  def run_prototype_structs(resource_module, prototype_name, opts \\ []) do
    Executor.execute_single_prototype(resource_module, prototype_name, opts, @strategy)
  end

  @doc """
  Build multiple prototypes as structs with dependency resolution.
  """
  def run_prototypes_structs(prototype_refs, opts \\ []) when is_list(prototype_refs) do
    Executor.execute_prototypes(prototype_refs, opts, @strategy)
  end

  @doc """
  Build all prototypes defined for a resource module as structs.
  """
  def run_all_prototypes_structs(resource_module, opts \\ []) do
    Executor.execute_all_prototypes(resource_module, opts, @strategy)
  end
end
