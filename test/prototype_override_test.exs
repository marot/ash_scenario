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
             AshScenario.run([{OverrideResource, :function_override}], domain: Domain)

    assert reason =~ "boom"
  end

  test "per-prototype action override uses specified action" do
    assert {:ok, resources} =
             AshScenario.run([{OverrideResource, :action_override}], domain: Domain)

    resource = resources[{OverrideResource, :action_override}]
    assert resource.name == "alternate"
  end

  test "falling back to default action still works" do
    assert {:ok, resources} =
             AshScenario.run([{OverrideResource, :default_behavior}], domain: Domain)

    resource = resources[{OverrideResource, :default_behavior}]
    assert resource.name == "default"
  end
end
