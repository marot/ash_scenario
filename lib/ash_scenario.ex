defmodule AshScenario do
  @moduledoc """
  Test data generation for your Ash application.

  AshScenario provides a DSL for defining named prototypes in your Ash resources,
  allowing you to create test data with automatic dependency resolution.

  ## Usage

  Add the DSL to your Ash resources:

      defmodule MyApp.Post do
        use Ash.Resource, extensions: [AshScenario.Dsl]

        prototypes do
          prototype :example_post,
            title: "My Example Post",
            content: "This is example content",
            blog_id: :example_blog  # Reference to prototype in Blog resource
        end
      end

      defmodule MyApp.Blog do
        use Ash.Resource, extensions: [AshScenario.Dsl]

        prototypes do
          prototype :example_blog,
            name: "My Example Blog"
        end
      end

  Then run scenarios:

      # Run prototypes with database persistence (default)
      AshScenario.run([
        {MyApp.Blog, :example_blog},
        {MyApp.Post, :example_post}
      ])

      # Run prototypes as in-memory structs
      AshScenario.run([
        {MyApp.Post, :example_post}
      ], strategy: :struct)

      # Run all prototypes for a resource
      AshScenario.run_all(MyApp.Post)
  """

  alias AshScenario.Scenario
  alias AshScenario.Scenario.Registry

  @doc """
  Start the scenario registry (should be called in your application supervision tree).
  """
  @spec start_registry(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_registry(opts \\ []) do
    Registry.start_link(opts)
  end

  @doc """
  Register prototypes from a resource module.
  This is typically called automatically when the resource is compiled.
  """
  @spec register_prototypes(module()) :: :ok | {:error, String.t()}
  def register_prototypes(resource_module) do
    Registry.register_prototypes(resource_module)
  end

  @doc """
  Execute prototypes with the specified strategy.

  ## Parameters

    * `prototype_refs` - List of prototype references as `{Module, :prototype_name}` tuples
    * `opts` - Options for execution

  ## Options

    * `:strategy` - Execution strategy (`:database` or `:struct`, defaults to `:database`)
    * `:domain` - The Ash domain to use (will be inferred if not provided)
    * `:overrides` - Map of attribute overrides keyed by prototype reference

  ## Examples

      # Execute with database persistence (default)
      {:ok, resources} = AshScenario.run([
        {User, :admin},
        {Post, :published_post}
      ])

      # Execute as in-memory structs
      {:ok, structs} = AshScenario.run([
        {User, :admin}
      ], strategy: :struct)

      # With overrides
      {:ok, resources} = AshScenario.run([
        {Post, :draft}
      ], overrides: %{{Post, :draft} => %{title: "Custom Title"}})
  """
  @spec run(list({module(), atom()}), keyword()) :: {:ok, map()} | {:error, any()}
  defdelegate run(prototype_refs, opts \\ []), to: Scenario

  @doc """
  Execute all prototypes defined for a resource module.

  ## Parameters

    * `resource_module` - The Ash resource module containing prototype definitions
    * `opts` - Options for execution

  ## Options

    * `:strategy` - Execution strategy (`:database` or `:struct`, defaults to `:database`)
    * `:domain` - The Ash domain to use (will be inferred if not provided)

  ## Examples

      {:ok, resources} = AshScenario.run_all(Post)
      {:ok, structs} = AshScenario.run_all(Post, strategy: :struct)
  """
  @spec run_all(module(), keyword()) :: {:ok, map()} | {:error, any()}
  defdelegate run_all(resource_module, opts \\ []), to: Scenario

  @doc """
  Run a named scenario from a test module.

  This function works with the scenario DSL for defining named test setups.

  ## Options

    * `:domain` - The Ash domain to use (will be inferred if not provided)
    * `:strategy` - Execution strategy (`:database` or `:struct`, defaults to `:database`)

  ## Examples

      {:ok, instances} = AshScenario.run_scenario(MyTest, :basic_setup)
      {:ok, instances} = AshScenario.run_scenario(MyTest, :basic_setup, domain: MyApp.Domain)
      {:ok, structs} = AshScenario.run_scenario(MyTest, :basic_setup, strategy: :struct)
  """
  @spec run_scenario(module(), atom(), keyword()) :: {:ok, map()} | {:error, String.t()}
  defdelegate run_scenario(test_module, scenario_name, opts \\ []), to: Scenario

  @doc """
  Get prototype information from a resource module.
  """
  defdelegate prototypes(resource), to: AshScenario.Info
  defdelegate prototype(resource, name), to: AshScenario.Info
  defdelegate has_prototypes?(resource), to: AshScenario.Info
  defdelegate prototype_names(resource), to: AshScenario.Info

  @doc """
  Clear all registered prototypes (useful for testing).
  """
  def clear_prototypes do
    Registry.clear_all()
  end

  @doc """
  Use this in your Ash resources to enable prototype support.

  ## Example

      defmodule MyApp.Post do
        use Ash.Resource, extensions: [AshScenario.Dsl]
        # ... your resource definition
      end
  """
  defmacro __using__(opts) do
    quote do
      use AshScenario.Dsl, unquote(opts)

      # Auto-register prototypes when the module is compiled
      @after_compile {AshScenario, :__register_prototypes__}
    end
  end

  @doc false
  def __register_prototypes__(env, _bytecode) do
    if AshScenario.Info.has_prototypes?(env.module) do
      case AshScenario.register_prototypes(env.module) do
        :ok ->
          :ok

        {:error, message} ->
          raise """
          Failed to register prototypes for #{inspect(env.module)}:

          #{message}
          """
      end
    end
  end

  @doc """
  Returns the DSL sections provided by AshScenario.
  Delegates to AshScenario.Dsl for the actual sections.
  """
  def sections do
    AshScenario.Dsl.sections()
  end

  @doc """
  Returns any DSL patches provided by AshScenario.
  Currently returns an empty list as no patches are defined.
  """
  def dsl_patches do
    []
  end
end
