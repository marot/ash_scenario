import Config

# Base logger configuration; keep default at :info for libraries
config :logger,
  level: :info,
  truncate: 8096,
  compile_time_purge_matching: [],
  backends: [:console]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:component, :resource, :ref, :trace_id]
