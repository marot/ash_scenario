defmodule PrototypeOverrideTest do
  use ExUnit.Case

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  test "per-prototype function override is respected" do
    assert {:error, reason} =
             AshScenario.run_prototype(OverrideResource, :function_override, domain: Domain)

    assert reason =~ "boom"
  end

  test "per-prototype action override uses specified action" do
    assert {:ok, resource} =
             AshScenario.run_prototype(OverrideResource, :action_override, domain: Domain)

    assert resource.name == "alternate"
  end

  test "falling back to default action still works" do
    assert {:ok, resource} =
             AshScenario.run_prototype(OverrideResource, :default_behavior, domain: Domain)

    assert resource.name == "default"
  end
end
