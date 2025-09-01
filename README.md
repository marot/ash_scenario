# AshScenario

Ash Scenario allows you to define reusable test data for your application. It provides two main approaches:

1. **Resource Definitions**: Reusable data templates defined in your Ash resources
2. **Test Scenarios**: Override and compose resources in test modules with named scenarios

It can be used for tests, staging environments, seeding, and more.

## Resource Definitions (formerly "scenarios")
Resources are defined on top of Ash resources using a DSL:
- The name of a test resource
- The default attributes  
- The default relationships
- Automatic dependency resolution

## Test Scenarios (new functionality)
When writing tests, you can define scenarios that override specific attributes from your resource definitions while maintaining automatic dependency resolution.


## Quick Start

### 1. Add the DSL to your resources

```elixir
defmodule Blog do
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

  attributes do
    uuid_primary_key :id
    attribute :name, :string do
      public? true
    end
  end

  actions do
    defaults [:read]
    create :create do
      accept [:name]
    end
  end

  # Define reusable test data resources
  resources do
    resource :example_blog,
      name: "Example Blog"

    resource :tech_blog,  
      name: "Tech Blog"
  end
end

defmodule Post do
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

  attributes do
    uuid_primary_key :id
    attribute :title, :string do
      public? true
    end
    attribute :content, :string do
      public? true
    end
  end

  relationships do
    belongs_to :blog, Blog do
      public? true
    end
  end

  actions do
    defaults [:read]
    create :create do
      accept [:title, :content, :blog_id]
    end
  end

  resources do
    resource :example_post,
      title: "A post title",
      content: "The content of the example post",
      blog_id: :example_blog  # Reference to example_blog resource

    resource :another_post,
      title: "Another post title", 
      content: "Different content",
      blog_id: :example_blog
  end
end
```

### 2. Create resources in your code

```elixir
# Create a single resource
{:ok, blog} = AshScenario.run_resource(Blog, :example_blog, domain: Domain)

# Create multiple resources with automatic dependency resolution  
{:ok, resources} = AshScenario.run_resources([
  {Blog, :example_blog},
  {Post, :example_post}
], domain: Domain)

# blog_id reference is automatically resolved to the created blog's ID
blog = resources[{Blog, :example_blog}]
post = resources[{Post, :example_post}]
assert post.blog_id == blog.id
```

### 3. Test Scenarios

Test scenarios let you override specific attributes while maintaining dependency resolution. They are fully implemented and ready to use:

```elixir
defmodule MyTest do
  use ExUnit.Case
  use AshScenario.Scenario

  scenario :basic_setup do
    another_post do
      title "Custom title for this test"
    end
  end

  scenario :with_custom_blog do
    tech_blog do
      name "My Custom Tech Blog"  
    end
    another_post do
      title "Post in custom blog"
      blog_id :tech_blog  # Use the custom blog
    end
  end

  test "basic scenario" do
    {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :basic_setup)
    assert resources.another_post.title == "Custom title for this test"
    assert resources.example_blog.name == "Example Blog"  # From resource defaults
  end
end
```

You can also pass a specific `:domain` if you don’t want it inferred from the resource modules:

```elixir
{:ok, resources} = AshScenario.Scenario.run(MyTest, :basic_setup, domain: MyApp.Domain)
```

## Key Features

- **Automatic Dependency Resolution**: Resources are created in the correct order based on relationships
- **Reference Resolution**: `:resource_name` references are automatically resolved to actual IDs
- **Reusable Definitions**: Define resources once, use them in multiple contexts
- **Override Support**: Test scenarios can override specific attributes while keeping defaults
- **Backward Compatibility**: Old "scenario" terminology still works via aliases

## Scenario API

```elixir
# Enable the Scenario DSL in a test module
use AshScenario.Scenario

# Define scenarios
scenario :my_setup do
  example_post do
    title "Overridden title"
  end
end

# Run a scenario
{:ok, resources} = AshScenario.Scenario.run(__MODULE__, :my_setup, domain: MyApp.Domain)

# Access created resources by their resource names (atoms)
resources.example_post.title
resources.example_blog.id
```

## API Reference

### Resource Management

```elixir
# New API (recommended)
AshScenario.run_resource(Module, :resource_name, opts)
AshScenario.run_resources(resource_list, opts) 
AshScenario.run_all_resources(Module, opts)

# Legacy API (still supported)  
AshScenario.run_scenario(Module, :resource_name, opts)
AshScenario.run_scenarios(resource_list, opts)
AshScenario.run_all_scenarios(Module, opts)
```

### Introspection

```elixir
# New API
AshScenario.resources(Module)         # Get all resource definitions
AshScenario.resource(Module, :name)   # Get specific resource definition
AshScenario.has_resources?(Module)    # Check if module has resources
AshScenario.resource_names(Module)    # Get all resource names

# Legacy API (aliases to new functions)
AshScenario.scenarios(Module)
AshScenario.scenario(Module, :name) 
AshScenario.has_scenarios?(Module)
AshScenario.scenario_names(Module)
```

## Architecture

- **Dependency Graph**: Resources are analyzed for dependencies and created in topological order
- **Reference Resolution**: Resource references (like `:example_blog`) are resolved to actual resource IDs at runtime
- **Registry**: A GenServer maintains the registry of all resource definitions across modules
