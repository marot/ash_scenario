defmodule AshScenario.Info do
  @moduledoc """
  Introspection functions for accessing resource information from resources.
  """

  @doc """
  Get all resources defined in a resource.
  """
  def resources(resource) do
    entities = Spark.Dsl.Extension.get_entities(resource, [:resources]) || []

    Enum.filter(entities, fn
      %AshScenario.Dsl.Resource{} -> true
      _ -> false
    end)
  end

  @doc """
  Get a specific resource by name from a resource.
  """
  def resource(resource, name) do
    resources(resource)
    |> Enum.find(fn resource_def -> 
      # Handle both our Resource struct and potential other structs
      case resource_def do
        %AshScenario.Dsl.Resource{ref: ^name} -> true
        %{ref: ^name} -> true
        _ -> false
      end
    end)
  end

  @doc """
  Check if a resource has any resources defined.
  """
  def has_resources?(resource) do
    resources(resource) != []
  end

  @doc """
  Get all resource names from a resource.
  """
  def resource_names(resource) do
    resources(resource)
    |> Enum.map(fn resource_def ->
      # Handle both our Resource struct and potential other structs
      case resource_def do
        %AshScenario.Dsl.Resource{ref: ref} -> ref
        %{ref: ref} -> ref
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Backward compatibility functions
  @doc "Deprecated: Use resources/1 instead"
  def scenarios(resource), do: resources(resource)
  
  @doc "Deprecated: Use resource/2 instead"
  def scenario(resource, name), do: resource(resource, name)
  
  @doc "Deprecated: Use has_resources?/1 instead"
  def has_scenarios?(resource), do: has_resources?(resource)
  
  @doc "Deprecated: Use resource_names/1 instead"
  def scenario_names(resource), do: resource_names(resource)

  @doc """
  Get the creation configuration for a resource module.

  Returns `%AshScenario.Dsl.Create{}` if defined, otherwise a default with action `:create`.
  """
  def create(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:resources])
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
