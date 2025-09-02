defmodule AshScenario.AbsentValidationTest do
  use ExUnit.Case, async: true
  use AshScenario.Scenario

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Ensure a clean registry and register our support resources
    AshScenario.clear_prototypes()
    AshScenario.register_prototypes(Blog)
    AshScenario.register_prototypes(Post)
    AshScenario.register_prototypes(Validated)
    :ok
  end

  # Scenarios for the minimal daily-activity-like resource
  scenario :custom_valid do
    custom_activity do
      # keep as-is from prototype
    end
  end

  scenario :library_valid do
    library_activity do
      # keep as-is from prototype
    end
  end

  test "runner passes with library activity" do
    assert {:ok, %Validated{}} =
             AshScenario.run_prototype(Validated, :library_activity, domain: Domain)
  end

  test "runner passes with custom activity" do
    assert {:ok, %Validated{}} =
             AshScenario.run_prototype(Validated, :custom_activity, domain: Domain)
  end

  test "fails when neither library nor both custom provided" do
    assert {:error, _} =
             AshScenario.run_prototype(Validated, :custom_activity,
               domain: Domain,
               overrides: %{custom_name: nil, custom_description: nil, activity_library_id: nil}
             )
  end

  test "fails when only one custom provided without library" do
    assert {:error, _} =
             AshScenario.run_prototype(Validated, :custom_activity,
               domain: Domain,
               overrides: %{custom_description: nil, activity_library_id: nil}
             )
  end

  test "planned_end_time required when planned_start_time present" do
    assert {:error, _} =
             AshScenario.run_prototype(Validated, :custom_activity,
               domain: Domain,
               overrides: %{planned_end_time: nil}
             )
  end

  test "planned_end_time must be after planned_start_time" do
    assert {:error, _} =
             AshScenario.run_prototype(Validated, :custom_activity,
               domain: Domain,
               overrides: %{planned_end_time: ~T[14:00:00]}
             )
  end

  test "scenario DSL custom activity passes" do
    assert {:ok, %{custom_activity: %Validated{}}} =
             AshScenario.Scenario.run(__MODULE__, :custom_valid, domain: Domain)
  end

  test "scenario DSL library activity passes" do
    assert {:ok, %{library_activity: %Validated{}}} =
             AshScenario.Scenario.run(__MODULE__, :library_valid, domain: Domain)
  end
end
