defmodule AshScenario.Dsl.Transformers.ValidateResources do
  @moduledoc """
  Transformer that validates resource definitions against the resource's
  attributes and relationships at compile time.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    resources = Transformer.get_entities(dsl_state, [:resources])
    
    case process_resources(dsl_state, resources) do
      :ok -> 
        {:ok, dsl_state}
      {:error, error} -> 
        {:error, error}
    end
  end

  defp process_resources(dsl_state, resources) do
    with {:ok, resource_module} <- get_resource_module(dsl_state),
         {:ok, valid_keys} <- get_valid_keys(dsl_state) do
      
      resources
      |> Enum.reduce_while(:ok, fn resource, :ok ->
        case validate_resource(resource, valid_keys, resource_module) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp validate_resource(resource, valid_keys, resource_module) do
    # The attributes are already in the right format from the DSL
    # Just validate them if we can
    if MapSet.size(valid_keys) > 0 do
      validate_resource_attributes(resource.attributes || [], valid_keys, resource.name, resource_module)
    else
      :ok
    end
  end

  defp get_resource_module(dsl_state) do
    case Transformer.get_persisted(dsl_state, :module) do
      nil -> {:error, "Could not determine resource module"}
      module -> {:ok, module}
    end
  end

  defp get_valid_keys(dsl_state) do
    # Try to get attributes and relationships from the DSL state
    attributes = 
      Transformer.get_entities(dsl_state, [:attributes])
      |> Enum.map(& &1.name)

    relationships = 
      Transformer.get_entities(dsl_state, [:relationships])
      |> Enum.flat_map(fn section ->
        case section do
          %{entities: entities} -> entities
          _ -> []
        end
      end)
      |> Enum.map(& &1.name)

    valid_keys = MapSet.new(attributes ++ relationships)
    
    # If we found keys, use them, otherwise skip validation
    {:ok, valid_keys}
  end

  defp validate_resource_attributes(attributes, valid_keys, resource_name, resource_module) do
    # Skip validation if we don't have valid keys (compilation time)
    if MapSet.size(valid_keys) == 0 do
      :ok
    else
      attributes
      |> Enum.reduce_while(:ok, fn {key, _value}, :ok ->
        if MapSet.member?(valid_keys, key) do
          {:cont, :ok}
        else
          error_msg = """
          Invalid attribute '#{key}' in resource '#{resource_name}' for resource #{inspect(resource_module)}.
          
          Valid attributes and relationships: #{valid_keys |> Enum.sort() |> Enum.join(", ")}
          """
          {:halt, {:error, error_msg}}
        end
      end)
    end
  end
end