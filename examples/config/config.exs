import Config

# Keep logger output lean during example runs.
config :logger, level: :warning
config :ash_scenario_examples, ash_domains: [AshScenario.Examples.Domain]
