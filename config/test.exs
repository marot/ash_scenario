import Config

# Verbose logging in test for easier debugging
config :logger, level: :warning

# Ash test convenience: avoid strict domain/resource inclusion checks in test
config :ash, :validate_domain_config_inclusion?, false
config :ash, :validate_domain_resource_inclusion?, false
