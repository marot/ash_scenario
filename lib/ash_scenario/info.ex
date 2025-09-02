defmodule AshScenario.Info do
  @moduledoc """
  Introspection functions for accessing prototype information from resource modules.
  """

  @doc """
  Get all prototypes defined in a resource module.
  """
  def prototypes(ash_resource) do
    entities = Spark.Dsl.Extension.get_entities(ash_resource, [:prototypes]) || []

    Enum.filter(entities, fn
      %AshScenario.Dsl.Prototype{} -> true
      _ -> false
    end)
  end

  @doc """
  Get a specific prototype by name from a resource module.
  """
  def prototype(ash_resource, name) do
    prototypes(ash_resource)
    |> Enum.find(fn resource_def ->
      # Handle both our Resource struct and potential other structs
      case resource_def do
        %AshScenario.Dsl.Prototype{ref: ^name} -> true
        %{ref: ^name} -> true
        _ -> false
      end
    end)
  end

  @doc """
  Check if a resource module has any prototypes defined.
  """
  def has_prototypes?(ash_resource) do
    prototypes(ash_resource) != []
  end

  @doc """
  Get all prototype names from a resource module.
  """
  def prototype_names(ash_resource) do
    prototypes(ash_resource)
    |> Enum.map(fn resource_def ->
      # Handle both our Resource struct and potential other structs
      case resource_def do
        %AshScenario.Dsl.Prototype{ref: ref} -> ref
        %{ref: ref} -> ref
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Get the creation configuration for a resource module.

  Returns `%AshScenario.Dsl.Create{}` if defined, otherwise a default with action `:create`.
  """
  def create(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:prototypes])
    |> Enum.find(fn
      %AshScenario.Dsl.Create{} -> true
      _ -> false
    end)
    |> case do
      %AshScenario.Dsl.Create{} = create -> create
      _ -> %AshScenario.Dsl.Create{action: :create}
    end
  end
end
