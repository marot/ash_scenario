import Config

# Base logger configuration; keep default at :info for libraries
config :logger,
  level: :warning,
  truncate: 8096,
  compile_time_purge_matching: [],
  backends: [:console]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:component, :resource, :ref, :trace_id]

# Configure tailwind (always configure it, the dep is optional)
config :tailwind,
  version: "4.0.9",
  ash_scenario: [
    args: ~w(
      --input=assets/css/ash_scenario.css
      --output=priv/static/ash_scenario.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
