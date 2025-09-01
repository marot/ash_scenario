defmodule AshScenario do
  @moduledoc """
  Test data generation for your Ash application.
  
  AshScenario provides a DSL for defining named resources in your Ash resources,
  allowing you to create test data with automatic dependency resolution.
  
  ## Usage
  
  Add the DSL to your resources:
  
      defmodule MyApp.Post do
        use Ash.Resource, extensions: [AshScenario.Dsl]
        
        resources do
          resource :example_post,
            title: "My Example Post",
            content: "This is example content",
            blog_id: :example_blog  # Reference to resource in Blog resource
        end
      end
      
      defmodule MyApp.Blog do
        use Ash.Resource, extensions: [AshScenario.Dsl]
        
        resources do
          resource :example_blog,
            name: "My Example Blog"
        end
      end
  
  Then run scenarios:
  
      # Run a single resource
      AshScenario.run_resource(MyApp.Post, :example_post)
      
      # Run multiple resources with dependency resolution
      AshScenario.run_resources([
        {MyApp.Blog, :example_blog},
        {MyApp.Post, :example_post}
      ])
      
      # Run all resources for a resource
      AshScenario.run_all_resources(MyApp.Post)
  """

  alias AshScenario.Scenario.{Registry, Runner}

  @doc """
  Start the scenario registry (should be called in your application supervision tree).
  """
  def start_registry(opts \\ []) do
    Registry.start_link(opts)
  end

  @doc """
  Register resources from a resource module.
  This is typically called automatically when the resource is compiled.
  """
  def register_resources(resource_module) do
    Registry.register_resources(resource_module)
  end

  @doc """
  Run a single resource by name from a resource.
  
  ## Options
  
    * `:domain` - The Ash domain to use (will be inferred if not provided)
  
  ## Examples
  
      AshScenario.run_resource(MyApp.Post, :example_post)
      AshScenario.run_resource(MyApp.Post, :example_post, domain: MyApp.Domain)
  """
  def run_resource(resource_module, resource_name, opts \\ []) do
    Runner.run_resource(resource_module, resource_name, opts)
  end

  @doc """
  Run multiple resources with automatic dependency resolution.
  
  ## Options
  
    * `:domain` - The Ash domain to use (will be inferred if not provided)
  
  ## Examples
  
      AshScenario.run_resources([
        {MyApp.Blog, :example_blog},
        {MyApp.Post, :example_post}
      ])
  """
  def run_resources(resource_refs, opts \\ []) when is_list(resource_refs) do
    Runner.run_resources(resource_refs, opts)
  end

  @doc """
  Run all resources defined in a resource.
  
  ## Options
  
    * `:domain` - The Ash domain to use (will be inferred if not provided)
  
  ## Examples
  
      AshScenario.run_all_resources(MyApp.Post)
  """
  def run_all_resources(resource_module, opts \\ []) do
    Runner.run_all_resources(resource_module, opts)
  end

  @doc """
  Get resource information from a resource.
  """
  defdelegate resources(resource), to: AshScenario.Info
  defdelegate resource(resource, name), to: AshScenario.Info
  defdelegate has_resources?(resource), to: AshScenario.Info
  defdelegate resource_names(resource), to: AshScenario.Info
  
  # Backward compatibility
  defdelegate scenarios(resource), to: AshScenario.Info
  defdelegate scenario(resource, name), to: AshScenario.Info
  defdelegate has_scenarios?(resource), to: AshScenario.Info
  defdelegate scenario_names(resource), to: AshScenario.Info

  @doc """
  Clear all registered resources (useful for testing).
  """
  def clear_resources do
    Registry.clear_all()
  end
  
  # Backward compatibility
  def clear_scenarios, do: clear_resources()
  def register_scenarios(resource_module), do: register_resources(resource_module)
  def run_scenario(resource_module, resource_name, opts \\ []), do: run_resource(resource_module, resource_name, opts)
  def run_scenarios(resource_refs, opts \\ []), do: run_resources(resource_refs, opts)
  def run_all_scenarios(resource_module, opts \\ []), do: run_all_resources(resource_module, opts)

  @doc """
  Use this in your resources to add resource support.
  
  ## Example
  
      defmodule MyApp.Post do
        use Ash.Resource, extensions: [AshScenario.Dsl]
        # ... your resource definition
      end
  """
  defmacro __using__(opts) do
    quote do
      use AshScenario.Dsl, unquote(opts)
      
      # Auto-register scenarios when the module is compiled
      @after_compile {AshScenario, :__register_scenarios__}
    end
  end

  @doc false
  def __register_scenarios__(env, _bytecode) do
    if AshScenario.Info.has_resources?(env.module) do
      AshScenario.register_resources(env.module)
    end
  end
end