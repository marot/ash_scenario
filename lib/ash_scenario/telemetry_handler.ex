defmodule AshScenario.TelemetryHandler do
  @moduledoc """
  Tracks which resources have been modified during tests.
  """

  use Agent

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> MapSet.new() end, name: name)
  end

  def get_changed_resources(agent_name \\ __MODULE__) do
    Agent.get(agent_name, & &1) |> MapSet.to_list()
  end

  def clear_changed_resources(agent_name \\ __MODULE__) do
    Agent.update(agent_name, fn _ -> MapSet.new() end)
  end

  defp add_changed_resource(resource, agent_name \\ __MODULE__) do
    Agent.update(agent_name, &MapSet.put(&1, resource))
  end

  def handle_event([:ash, _domain, action, :stop] = event, _measurements, metadata, config) 
      when action in [:create, :update, :destroy] do
    agent_name = Keyword.get(config, :agent_name, __MODULE__)
    
    IO.puts("DEBUG: Handling event: #{inspect(event)}")
    IO.puts("DEBUG: Metadata: #{inspect(metadata)}")
    
    case extract_resource_info(metadata) do
      nil -> 
        IO.puts("DEBUG: No resource info extracted")
        :ok
      resource_info -> 
        IO.puts("DEBUG: Adding resource info: #{inspect(resource_info)}")
        add_changed_resource(resource_info, agent_name)
    end
  end

  def handle_event(event, _measurements, _metadata, _config) do
    IO.puts("DEBUG: Ignoring event: #{inspect(event)}")
    :ok
  end

  defp extract_resource_info(%{resource: resource} = metadata) when is_atom(resource) do
    primary_keys = get_primary_keys(resource, metadata)
    
    %{
      resource: resource,
      primary_keys: primary_keys
    }
  end

  defp extract_resource_info(_metadata), do: nil

  defp get_primary_keys(resource, %{result: result}) when is_map(result) do
    resource
    |> Ash.Resource.Info.primary_key()
    |> Enum.map(fn key -> {key, Map.get(result, key)} end)
    |> Enum.into(%{})
  end

  defp get_primary_keys(_resource, _metadata), do: %{}

  def attach(opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, "ash-scenario-telemetry")
    agent_name = Keyword.get(opts, :agent_name, __MODULE__)
    
    events = [
      [:ash, :*, :create, :stop],
      [:ash, :*, :update, :stop],
      [:ash, :*, :destroy, :stop]
    ]
    
    IO.puts("DEBUG: Attaching telemetry handler with ID: #{handler_id}")
    IO.puts("DEBUG: Subscribing to events: #{inspect(events)}")
    
    :telemetry.attach_many(
      handler_id,
      events,
      &__MODULE__.handle_event/4,
      [agent_name: agent_name]
    )
    
    # Also attach a debug handler to catch ALL ash events
    :telemetry.attach_many(
      "#{handler_id}_debug",
      [[:ash | List.duplicate(:*, 10)]],
      fn event, _, _, _ -> IO.puts("DEBUG: Ash event fired: #{inspect(event)}") end,
      nil
    )
  end

  def detach(handler_id \\ "ash-scenario-telemetry") do
    :telemetry.detach(handler_id)
  end

  def setup_for_test(test_name \\ nil) do
    unique_id = :erlang.unique_integer()
    agent_name = :"test_agent_#{unique_id}_#{test_name || "default"}"
    handler_id = "test_handler_#{unique_id}"
    
    {:ok, _pid} = start_link(name: agent_name)
    attach(handler_id: handler_id, agent_name: agent_name)
    
    %{agent_name: agent_name, handler_id: handler_id}
  end

  def teardown_test(%{handler_id: handler_id}) do
    detach(handler_id)
    detach("#{handler_id}_debug")
  end

end