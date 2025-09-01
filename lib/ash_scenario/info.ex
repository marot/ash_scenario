defmodule AshScenario.Info do
  @moduledoc """
  Introspection functions for accessing resource information from resources.
  """

  @doc """
  Get all resources defined in a resource.
  """
  def resources(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:resources]) || []
  end

  @doc """
  Get a specific resource by name from a resource.
  """
  def resource(resource, name) do
    resources(resource)
    |> Enum.find(fn resource -> resource.name == name end)
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
    |> Enum.map(& &1.name)
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
end