defmodule AshScenario.Sequence do
  @moduledoc """
  Manages sequence counters for runtime attribute evaluation.

  Automatically started and managed internally when MFA tuples are used
  in prototype attribute definitions.

  ## Usage

  Sequences are automatically incremented when prototypes use MFA tuples:

      prototype :user do
        attr :email, {MyModule, :unique_email, []}
      end

  Each attribute gets its own sequence based on the key
  `{resource_module, prototype_ref, attr_name}`.

  Sequences are automatically reset between tests when using ExUnit.
  """

  use Agent

  @doc false
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Get the next value in a sequence for a given key.

  The key is typically `{resource_module, prototype_ref, attr_name}`.

  ## Examples

      iex> AshScenario.Sequence.next({User, :test_user, :email})
      0
      iex> AshScenario.Sequence.next({User, :test_user, :email})
      1
      iex> AshScenario.Sequence.next({User, :test_user, :username})
      0
  """
  def next(key) do
    ensure_started()

    Agent.get_and_update(__MODULE__, fn state ->
      current = Map.get(state, key, 0)
      {current, Map.put(state, key, current + 1)}
    end)
  end

  @doc """
  Reset all sequences to their initial state.

  This is automatically called in test setups to ensure test isolation.

  ## Examples

      setup do
        AshScenario.Sequence.reset()
        :ok
      end
  """
  def reset do
    if Process.whereis(__MODULE__) do
      Agent.update(__MODULE__, fn _ -> %{} end)
    end
  end

  defp ensure_started do
    unless Process.whereis(__MODULE__) do
      {:ok, _} = start_link([])
    end
  end
end
