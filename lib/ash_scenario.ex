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

      <!--# Run a single prototype-->
      AshScenario.run_prototype(MyApp.Post, :example_post)

      # Run multiple prototypes with dependency resolution
      AshScenario.run_prototypes([
        {MyApp.Blog, :example_blog},
        {MyApp.Post, :example_post}
      ])

      # Run all prototypes for a resource
      AshScenario.run_all_prototypes(MyApp.Post)
  """

  alias AshScenario.Scenario.{Registry, Runner, StructBuilder}

  @doc """
  Start the scenario registry (should be called in your application supervision tree).
  """
  def start_registry(opts \\ []) do
    Registry.start_link(opts)
  end

  @doc """
  Register prototypes from a resource module.
  This is typically called automatically when the resource is compiled.
  """
  def register_prototypes(resource_module) do
    Registry.register_prototypes(resource_module)
  end

  @doc """
  Run a single prototype by name from a resource module.

  ## Options

    * `:domain` - The Ash domain to use (will be inferred if not provided)

  ## Examples

      AshScenario.run_prototype(MyApp.Post, :example_post)
      AshScenario.run_prototype(MyApp.Post, :example_post, domain: MyApp.Domain)
  """
  def run_prototype(resource_module, prototype_name, opts \\ []) do
    Runner.run_prototype(resource_module, prototype_name, opts)
  end

  @doc """
  Run multiple prototypes with automatic dependency resolution.

  ## Options

    * `:domain` - The Ash domain to use (will be inferred if not provided)

  ## Examples

      AshScenario.run_prototypes([
        {MyApp.Blog, :example_blog},
        {MyApp.Post, :example_post}
      ])
  """
  def run_prototypes(prototype_refs, opts \\ []) when is_list(prototype_refs) do
    Runner.run_prototypes(prototype_refs, opts)
  end

  @doc """
  Run all prototypes defined in a resource module.

  ## Options

    * `:domain` - The Ash domain to use (will be inferred if not provided)

  ## Examples

      AshScenario.run_all_prototypes(MyApp.Post)
  """
  def run_all_prototypes(resource_module, opts \\ []) do
    Runner.run_all_prototypes(resource_module, opts)
  end

  @doc """
  Get prototype information from a resource module.
  """
  defdelegate prototypes(resource), to: AshScenario.Info
  defdelegate prototype(resource, name), to: AshScenario.Info
  defdelegate has_prototypes?(resource), to: AshScenario.Info
  defdelegate prototype_names(resource), to: AshScenario.Info

  @doc """
  Create a single prototype as a struct without database persistence.

  This is useful for generating test data for stories or other use cases
  where you need the data structure but don't want to persist to the database.

  ## Examples

      AshScenario.create_struct(MyApp.Post, :example_post)
      AshScenario.create_struct(MyApp.Post, :example_post, title: "Override")
  """
  def create_struct(resource_module, prototype_name, opts \\ []) do
    StructBuilder.run_prototype_structs(resource_module, prototype_name, opts)
  end

  @doc """
  Create multiple prototypes as structs with automatic dependency resolution.

  All dependencies will be created as structs in memory without database persistence.

  ## Examples

      AshScenario.create_structs([
        {MyApp.Blog, :example_blog},
        {MyApp.Post, :example_post}
      ])
  """
  def create_structs(prototype_refs, opts \\ []) when is_list(prototype_refs) do
    StructBuilder.run_prototypes_structs(prototype_refs, opts)
  end

  @doc """
  Create all prototypes defined in a resource module as structs.

  ## Examples

      AshScenario.create_all_structs(MyApp.Post)
  """
  def create_all_structs(resource_module, opts \\ []) do
    StructBuilder.run_all_prototypes_structs(resource_module, opts)
  end

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
      AshScenario.register_prototypes(env.module)
    end
  end
end
