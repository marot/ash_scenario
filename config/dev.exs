import Config

# Git Ops configuration for automated versioning and changelog management
config :git_ops,
  mix_project: AshScenario.MixProject,
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/marot/ash_scenario",
  manage_mix_version?: true,
  manage_readme_version?: "README.md",
  version_tag_prefix: "v"

# somewhere in your config file
if Mix.env() == :dev do
  config :git_hooks,
    auto_install: true,
    verbose: true,
    hooks: [
      pre_commit: [
        tasks: [
          {AshScenario.PreCommit.Formatter, :run}
        ]
      ]
    ]
end
