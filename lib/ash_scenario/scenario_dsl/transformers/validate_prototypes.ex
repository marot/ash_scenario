defmodule AshScenario.ScenarioDsl.Transformers.ValidatePrototypes do
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def transform(dsl_state) do
    scenarios = Transformer.get_entities(dsl_state, [:scenarios])

    # Get available prototypes from the application
    available_prototypes = get_available_prototypes(dsl_state)

    Enum.reduce_while(scenarios, {:ok, dsl_state}, fn scenario, {:ok, dsl} ->
      case validate_scenario_prototypes(scenario, available_prototypes) do
        :ok -> {:cont, {:ok, dsl}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp validate_scenario_prototypes(scenario, available_prototypes) do
    Enum.reduce_while(scenario.prototypes || [], :ok, fn prototype_override, :ok ->
      if prototype_exists?(prototype_override.ref, available_prototypes) do
        {:cont, :ok}
      else
        error =
          Spark.Error.DslError.exception(
            message:
              "Scenario '#{scenario.name}' references unknown prototype '#{inspect(prototype_override.ref)}'",
            path: [:scenarios, scenario.name]
          )

        {:halt, {:error, error}}
      end
    end)
  end

  defp prototype_exists?(ref, available_prototypes) do
    # Check if prototype ref exists in available prototypes
    Map.has_key?(available_prototypes, ref)
  end

  defp get_available_prototypes(_dsl_state) do
    # Gather prototypes from all loaded modules using AshScenario.Dsl
    discover_resource_modules()
    |> Enum.reduce(%{}, fn module, acc ->
      try do
        if function_exported?(module, :spark_dsl_config, 0) and uses_ash_scenario_dsl?(module) do
          prototypes = AshScenario.Info.prototypes(module)

          Enum.reduce(prototypes, acc, fn prototype, inner_acc ->
            # Support both simple refs and module-scoped refs
            simple_ref = prototype.ref
            scoped_ref = {module, prototype.ref}

            inner_acc
            |> Map.put(simple_ref, {module, prototype})
            |> Map.put(scoped_ref, {module, prototype})
          end)
        else
          acc
        end
      rescue
        _ -> acc
      end
    end)
  end

  defp discover_resource_modules do
    # Get all loaded modules
    :code.all_loaded()
    |> Enum.map(fn {module, _path} -> module end)
  end

  defp uses_ash_scenario_dsl?(module) do
    try do
      # Check if the module uses our DSL extension
      case module.spark_dsl_config() do
        %{extensions: extensions} ->
          AshScenario.Dsl in extensions

        _ ->
          false
      end
    rescue
      _ -> false
    end
  end
end
