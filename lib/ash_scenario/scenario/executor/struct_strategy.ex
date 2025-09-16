defmodule AshScenario.Scenario.Executor.StructStrategy do
  @moduledoc """
  Execution strategy for creating structs without database persistence.

  This strategy builds structs directly without using Ash.create,
  suitable for generating test data that doesn't need to be persisted.
  """

  @behaviour AshScenario.Scenario.Executor

  alias AshScenario.Scenario.Helpers

  @impl true
  def create_resource(resource_module, attributes, _opts) do
    # For struct mode, we DON'T extract tenant info - we keep the attributes as-is
    # because structs should keep relationship references as structs, not IDs

    # Get primary key field(s)
    primary_key = Ash.Resource.Info.primary_key(resource_module)

    # Generate ID if needed and not provided
    attributes_with_id =
      case {primary_key, Map.has_key?(attributes, :id)} do
        {[:id], false} ->
          Map.put(attributes, :id, Ash.UUID.generate())

        _ ->
          attributes
      end

    # Add timestamps if the resource has them and they're not provided
    now = DateTime.utc_now()

    attributes_with_timestamps =
      attributes_with_id
      |> maybe_add_timestamp(:inserted_at, now, resource_module)
      |> maybe_add_timestamp(:updated_at, now, resource_module)

    # Create the struct
    struct = struct(resource_module, attributes_with_timestamps)

    {:ok, struct}
  rescue
    error ->
      {:error, "Failed to build struct: #{inspect(error)}"}
  end

  @impl true
  def wrap_execution(_ordered_prototypes, _opts, execution_fn) do
    # For struct mode, we don't need transactions
    # Just execute the function directly
    execution_fn.()
  end

  @doc """
  Custom attribute resolution for struct mode.

  In struct mode, we keep relationship references as structs instead of
  extracting IDs like the database strategy does.
  """
  def resolve_attributes(attributes, resource_module, created_structs) do
    resolved =
      attributes
      |> Enum.map(fn {key, value} ->
        {:ok, resolved_value} =
          resolve_struct_attribute_value(value, key, resource_module, created_structs)

        {key, resolved_value}
      end)
      |> Map.new()

    {:ok, resolved}
  end

  # Private helpers

  defp resolve_struct_attribute_value(value, attr_name, resource_module, created_structs)
       when is_atom(value) do
    if Helpers.relationship_attribute?(resource_module, attr_name) do
      case Helpers.related_module_for_attr(resource_module, attr_name) do
        {:ok, related_module} ->
          case Helpers.find_referenced_resource(value, related_module, created_structs) do
            {:ok, resource} ->
              # Return the struct itself for struct mode, not the ID
              {:ok, resource}

            :not_found ->
              # Keep as atom if not found
              {:ok, value}
          end

        :error ->
          {:ok, value}
      end
    else
      # Not a relationship, keep as-is
      {:ok, value}
    end
  end

  defp resolve_struct_attribute_value(value, _attr_name, _resource_module, _created_structs),
    do: {:ok, value}

  defp maybe_add_timestamp(attributes, field, default_value, resource_module) do
    if Map.has_key?(attributes, field) do
      attributes
    else
      # Check if the resource has this timestamp field
      case Ash.Resource.Info.attribute(resource_module, field) do
        nil -> attributes
        _attr -> Map.put(attributes, field, default_value)
      end
    end
  end
end
