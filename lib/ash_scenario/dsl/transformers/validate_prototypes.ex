defmodule AshScenario.Dsl.Transformers.ValidatePrototypes do
  @moduledoc """
  Transformer that validates prototype definitions against the resource's
  attributes and relationships at compile time.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    prototypes =
      Transformer.get_entities(dsl_state, [:prototypes])
      |> Enum.filter(fn
        %AshScenario.Dsl.Prototype{} -> true
        _ -> false
      end)

    case process_prototypes(dsl_state, prototypes) do
      :ok ->
        {:ok, dsl_state}

      {:error, error} ->
        {:error, error}
    end
  end

  defp process_prototypes(dsl_state, prototypes) do
    with {:ok, resource_module} <- get_resource_module(dsl_state),
         {:ok, valid_keys} <- get_valid_keys(dsl_state) do
      prototypes
      |> Enum.reduce_while(:ok, fn prototype, :ok ->
        case validate_prototype(prototype, valid_keys, resource_module) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp validate_prototype(prototype, valid_keys, resource_module) do
    # The attributes are already in the right format from the DSL
    # Just validate them if we can
    if MapSet.size(valid_keys) > 0 do
      validate_prototype_attributes(prototype, valid_keys, prototype.ref, resource_module)
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

    relationship_entities =
      Transformer.get_entities(dsl_state, [:relationships])
      |> Enum.flat_map(fn item ->
        cond do
          is_map(item) and Map.has_key?(item, :entities) -> Map.get(item, :entities, [])
          true -> [item]
        end
      end)

    # Allow using either the relationship name (e.g., :blog) or its source attribute (e.g., :blog_id)
    relationship_source_attrs =
      relationship_entities
      |> Enum.map(fn rel ->
        cond do
          is_map(rel) and is_atom(Map.get(rel, :source_attribute)) ->
            Map.get(rel, :source_attribute)

          is_map(rel) and is_atom(Map.get(rel, :attribute)) ->
            Map.get(rel, :attribute)

          is_map(rel) and is_atom(Map.get(rel, :name)) ->
            String.to_atom("#{rel.name}_id")

          true ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Only support relationship source attributes (e.g., :blog_id), not relationship names (e.g., :blog)
    valid_keys = MapSet.new(attributes ++ relationship_source_attrs)

    # If we found keys, use them, otherwise skip validation
    {:ok, valid_keys}
  end

  defp validate_prototype_attributes(prototype, valid_keys, prototype_name, resource_module) do
    attributes = prototype.attributes || []
    virtuals = MapSet.new(prototype.virtuals || [])
    # Skip validation if we don't have valid keys (compilation time)
    if MapSet.size(valid_keys) == 0 do
      :ok
    else
      attributes
      |> Enum.reduce_while(:ok, fn {key, _value}, :ok ->
        # Allow keys that are defined on the resource OR explicitly marked virtual
        if MapSet.member?(valid_keys, key) or MapSet.member?(virtuals, key) do
          {:cont, :ok}
        else
          error_msg = """
          Invalid attribute '#{key}' in prototype '#{prototype_name}' for resource #{inspect(resource_module)}.

          Valid attributes and relationships: #{valid_keys |> Enum.sort() |> Enum.join(", ")}
          """

          {:halt, {:error, error_msg}}
        end
      end)
    end
  end
end
