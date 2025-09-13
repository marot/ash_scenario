defmodule AshScenario.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      AshScenario.Scenario.Registry
    ]

    opts = [strategy: :one_for_one, name: AshScenario.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
