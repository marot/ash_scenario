import Config

# Git Ops configuration for automated versioning and changelog management
config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/marot/ash_scenario",
  github_handle_lookup?: true,
  github_api_base_url: "https://api.github.com",
  # Instructs the tool to manage your mix version in your `mix.exs` file
  # See below for more information
  manage_mix_version?: true,
  # Instructs the tool to manage the version in your README.md
  # Pass in `true` to use `"README.md"` or a string to customize
  manage_readme_version: "README.md",
  version_tag_prefix: "v",
  types: [
    # Makes an allowed commit type called `tidbit` that is not
    # shown in the changelog
    tidbit: [
      hidden?: true
    ],
    # Makes an allowed commit type called `important` that gets
    # a section in the changelog with the header "Important Changes"
    important: [
      header: "Important Changes"
    ]
  ]

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
