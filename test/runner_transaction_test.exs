defmodule RunnerTransactionTest do
  use ExUnit.Case

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    case :mnesia.clear_table(:transaction_resources) do
      {:atomic, :ok} -> :ok
      {:aborted, {:no_exists, :transaction_resources}} -> :ok
      {:aborted, {:no_exists, _}} -> :ok
      _ -> :ok
    end

    :ok
  end

  test "previous creations are rolled back when a later prototype fails" do
    assert {:error, reason} =
             AshScenario.run(
               [
                 {TransactionResource, :ok_entry},
                 {TransactionResource, :failing_entry}
               ],
               domain: Domain
             )

    assert reason =~ "forced_failure"

    if Ash.DataLayer.data_layer_can?(TransactionResource, :transact) do
      assert {:ok, []} = Ash.read(TransactionResource, domain: Domain)
    else
      IO.puts("TransactionResource data layer does not support transactions - skipping assertion")
    end
  end
end
