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

You can also pass a specific `:domain` if you don't want it inferred from the resource modules:

```elixir
{:ok, resources} = AshScenario.Scenario.run(MyTest, :basic_setup, domain: MyApp.Domain)
```

### 4. Custom Functions

You can specify a custom function to create resources instead of using the default `Ash.create` action. This is useful for complex setup logic, factory functions, or integration with existing test data builders:

```elixir
defmodule MyFactory do
  def create_blog(attributes, _opts) do
    # Custom creation logic
    blog = %Blog{
      id: Ash.UUID.generate(),
      name: attributes[:name] || "Default Blog"
    }
    {:ok, blog}
  end

  def create_post_with_tags(attributes, _opts) do
    # More complex creation with additional setup
    post = %Post{
      id: Ash.UUID.generate(),
      title: attributes[:title],
      blog_id: attributes[:blog_id],
      status: attributes[:status] || :draft
    }
    
    # Custom logic here - add tags, send notifications, etc.
    {:ok, post}
  end
end

defmodule Blog do
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

  # ... attributes, actions, etc. ...

  resources do
    resource :factory_blog,
      name: "Factory Blog",
      function: {MyFactory, :create_blog, []}

    resource :custom_post,
      title: "Custom Post",
      status: :published,     # Preserved as atom (not resolved)
      blog_id: :factory_blog, # Resolved to actual blog ID
      function: {MyFactory, :create_post_with_tags, []}
  end
end
```

#### Custom Function Requirements

Your custom function must:
- Accept `(resolved_attributes, opts)` as parameters
- Return `{:ok, created_resource}` or `{:error, reason}`
- Handle the resolved attributes where relationship references are already converted to IDs

```elixir
def my_custom_function(resolved_attributes, opts) do
  # resolved_attributes example:
  # %{
  #   name: "Factory Blog",
  #   status: :published,           # Non-relationship atoms preserved
  #   blog_id: "uuid-string-here"   # Relationship references resolved to IDs
  # }
  
  # Your custom creation logic here
  {:ok, created_resource}
end
```

### Scenario Extension (Inheritance)

Scenarios can extend other scenarios using the `extends` option, allowing you to build hierarchical test setups:

```elixir
defmodule MyTest do
  use ExUnit.Case
  use AshScenario.Scenario

  # Base scenario
  scenario :base_setup do
    example_blog do
      name "Base Blog"
    end
    
    example_post do
      title "Base Post"
      content "Base content"
    end
  end

  # Extended scenario - inherits from base and adds/overrides
  scenario :extended_setup, extends: :base_setup do
    example_post do
      title "Extended Post"  # Override title
      # content is inherited as "Base content"
    end
    
    another_post do  # Add new resource
      title "Additional post"
      content "More content"
    end
  end

  test "extended scenario" do
    {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :extended_setup)
    
    # Has inherited resources
    assert resources.example_blog.name == "Base Blog"
    assert resources.example_post.content == "Base content"  # Inherited
    
    # Has overridden attributes  
    assert resources.example_post.title == "Extended Post"  # Overridden
    
    # Has new resources from extension
    assert resources.another_post.title == "Additional post"
  end
end
```

## Key Features

- **Automatic Dependency Resolution**: Resources are created in the correct order based on relationships
- **Reference Resolution**: `:resource_name` references are automatically resolved to actual IDs
- **Reusable Definitions**: Define resources once, use them in multiple contexts
- **Override Support**: Test scenarios can override specific attributes while keeping defaults
- **Scenario Extension**: Build hierarchical scenarios using `extends: :base_scenario`
- **Custom Functions**: Use any function as an alternative to the default create action
- **Hardened Resolution**: Only relationship attributes are resolved; other atoms are preserved
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
