defmodule AshScenario.MixProject do
  use Mix.Project

  @description """
  Test data generation for your Ash application.
  """

  @version "0.0.1"

  @source_url "https://github.com/marot/ash_scenario"

  def project do
    [
      app: :ash_scenario,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      consolidate_protocols: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:ash, :mix]],
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      preferred_cli_env: [
        "test.create": :test,
        "test.migrate": :test,
        "test.rollback": :test,
        "test.migrate_tenants": :test,
        "test.check_migrations": :test,
        "test.drop": :test,
        "test.generate_migrations": :test,
        "test.reset": :test,
        "test.full_reset": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AshScenario.Application, []}
    ]
  end

  defp elixirc_paths(:test) do
    ["test/support/", "lib/"]
  end

  defp elixirc_paths(_env) do
    ["lib/"]
  end

  defp package do
    [
      name: :ash_scenario,
      licenses: ["MIT"],
      maintainers: "Marco Rotili",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* usage-rules.md
      CHANGELOG* documentation),
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, ash_version("~> 3.5 and >= 3.5.5")}
    ]
  end

  defp aliases do
    [
      "spark.formatter": "spark.formatter --extensions AshScenario",
      sobelow: "sobelow --skip",
      credo: "credo --strict",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshScenario",
      "test.generate_migrations": "ash_postgres.generate_migrations",
      "test.check_migrations": "ash_postgres.generate_migrations --check",
      "test.migrate_tenants": "ash_postgres.migrate --tenants",
      "test.migrate": "ash_postgres.migrate",
      "test.rollback": "ash_postgres.rollback",
      "test.create": "ash_postgres.create",
      "test.full_reset": ["test.generate_migrations", "test.reset"],
      "test.reset": ["test.drop", "test.create", "test.migrate", "ash_postgres.migrate --tenants"],
      "test.drop": "ash_postgres.drop"
    ]
  end

  defp ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil -> default_version
      "local" -> [path: "../ash", override: true]
      "main" -> [git: "https://github.com/ash-project/ash.git", override: true]
      version -> "~> #{version}"
    end
  end
end
