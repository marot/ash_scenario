# AshScenario

Ash Scenario allows you to define reusable test data for your application. It provides two main approaches:

1. **Prototype Definitions**: Reusable data templates defined in your Ash resources
2. **Test Scenarios**: Override and compose prototypes in test modules with named scenarios

It can be used for tests, staging environments, seeding, and more.

## Prototype Definitions
Prototypes are defined on top of Ash resources using a DSL:
- The name of a test resource
- The default attributes
- The default relationships
- Automatic dependency resolution

## Test Scenarios
When writing tests, you can define scenarios that override specific attributes from your prototype definitions while maintaining automatic dependency resolution.


## Quick Start

### Examples directory

For a self-contained demo, explore the Mix project in `examples/`:

```bash
cd examples
mix deps.get
mix test
```

It defines a multi-tenant launch workspace domain (organizations, projects,
tasks, and checklist items) with scenarios that exercise dependency resolution,
overrides, and tenant-aware updates.

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

  # Define reusable test data prototypes
  prototypes do
    prototype :example_blog do
      attr :name, "Example Blog"
    end

    prototype :tech_blog do
      attr :name, "Tech Blog"
    end
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

  prototypes do
    prototype :example_post do
      attr :title, "A post title"
      attr :content, "The content of the example post"
      # Reference to example_blog prototype
      attr :blog_id, :example_blog
    end

    prototype :another_post do
      attr :title, "Another post title"
      attr :content, "Different content"
      attr :blog_id, :example_blog
    end
  end
end
```

### 2. Create prototypes in your code

```elixir
# Create a single prototype (returns a map)
{:ok, resources} = AshScenario.run([{Blog, :example_blog}], domain: Domain)
blog = resources[{Blog, :example_blog}]

# Create multiple prototypes with automatic dependency resolution
{:ok, resources} = AshScenario.run([
  {Blog, :example_blog},
  {Post, :example_post}
], domain: Domain)

# blog_id reference is automatically resolved to the created blog's ID
blog = resources[{Blog, :example_blog}]
post = resources[{Post, :example_post}]
assert post.blog_id == blog.id
```

Overrides (first-class)

You can override attributes inline when creating prototypes:

```elixir
# Single prototype with overrides
{:ok, resources} = AshScenario.run(
  [{Post, :example_post}],
  domain: Domain,
  overrides: %{title: "Custom title"}
)
post = resources[{Post, :example_post}]

# Multiple prototypes: per-tuple overrides
{:ok, resources} = AshScenario.run([
  {Blog, :example_blog, %{name: "Custom Blog"}},
  {Post, :example_post, %{title: "Custom Post"}}
], domain: Domain)

# Multiple prototypes: top-level overrides map keyed by {Module, :ref}
overrides = %{
  {Blog, :example_blog} => %{name: "Top-level Blog"},
  {Post, :example_post} => %{title: "Top-level Post"}
}
{:ok, resources} = AshScenario.run([
  {Blog, :example_blog},
  {Post, :example_post}
], domain: Domain, overrides: overrides)
```

Notes:
- Overrides are merged with the prototype’s defined attributes before relationship resolution.
- Relationship atoms you set (like `blog_id: :example_blog`) still resolve to IDs as usual.
- For a single-resource call, `overrides: %{...}` is shorthand — no tuple key is needed.

### 3. Test Scenarios

Test scenarios let you override specific attributes while maintaining dependency resolution. They are fully implemented and ready to use:

```elixir
defmodule MyTest do
  use ExUnit.Case
  use AshScenario.Scenario

    scenario :basic_setup do
      prototype :another_post do
        attr(:title, "Custom title for this test")
      end
    end

    scenario :with_custom_blog do
      prototype :tech_blog do
        attr(:name, "My Custom Tech Blog")
      end
      prototype :another_post do
        attr(:title, "Post in custom blog")
        attr(:blog_id, :tech_blog)  # Use the custom blog
      end
  end

  test "basic scenario" do
    {:ok, resources} = AshScenario.run_scenario(__MODULE__, :basic_setup)
    assert resources.another_post.title == "Custom title for this test"
    assert resources.example_blog.name == "Example Blog"  # From prototype defaults
  end
end
```

You can also pass a specific `:domain` if you don't want it inferred from the resource modules:

```elixir
{:ok, resources} = AshScenario.run_scenario(MyTest, :basic_setup, domain: MyApp.Domain)
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

  prototypes do
    # Module-level create configuration for this resource module
    create function: {MyFactory, :create_blog, []}

    prototype :factory_blog do
      attr :name, "Factory Blog"
    end
  end
end

defmodule Post do
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

  # ... attributes, relationships, actions ...

  prototypes do
    # Separate module-level configuration for Post creation
    create function: {MyFactory, :create_post_with_tags, []}

    prototype :custom_post do
      attr :title, "Custom Post"
      # Preserved as atom (not a relationship)
      attr :status, :published
      # Resolved to actual blog ID
      attr :blog_id, :factory_blog
    end
  end
end
```

#### Custom Function Requirements

Your custom function must:
- Accept `(resolved_attributes, opts)` as parameters
- Return `{:ok, created_resource}` or `{:error, reason}`
- Handle the resolved attributes where relationship references are already converted to IDs

Notes:
- You can configure creation at the module level (via `create ...`) or per resource (via `action:`/`function:` on a specific `resource`).
- Precedence: resource.function > resource.action > module-level create.function > module-level create.action (default `:create`).

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
      prototype :example_post do
        attr(:title, "Base Post 123lshdfkjglsdfg")
        # attr(:content, "Base content")
      end
    end

    # Extended scenario - inherits from base and adds/overrides
    scenario :extended_setup do
      extends(:base_setup)

      prototype :example_post do
        attr(:title, "Extended Post")  # Override title
        # content is inherited as "Base content"
      end

      prototype :another_post do  # Add new resource
        attr(:title, "Additional post")
        attr(:content, "More content")
      end
    end

  test "extended scenario" do
    {:ok, resources} = AshScenario.run_scenario(__MODULE__, :extended_setup)

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
- **Virtual Attributes**: Pass action arguments (not stored attributes) via `virtual: true`

## Scenario API

### Virtual Attributes (Action Arguments)

Some create actions accept arguments that are not stored as attributes on the resource (e.g., `password`, `password_confirmation` for an auth flow). You can include these in prototype definitions by marking them as virtual. Virtual attributes skip compile-time validation against the resource schema and are passed into the create action input, allowing Ash to treat them as action arguments.

```elixir
defmodule User do
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

  attributes do
    uuid_primary_key :id
    attribute :email, :string do
      public? true
    end
  end

  actions do
    create :register do
      accept [:email]
      # Action arguments that are not attributes
      argument :password, :string, allow_nil?: false
      argument :password_confirmation, :string, allow_nil?: false
    end
  end

  prototypes do
    create action: :register

    prototype :admin_user do
      attr :email, "admin@example.com"
      attr :password, "s3cret", virtual: true
      attr :password_confirmation, "s3cret", virtual: true
    end
  end
end
```

Notes:
- Virtual attributes are not validated against the resource's attributes/relationships.
- They are included in the map passed to `Ash.Changeset.for_create/3`, so if your create action defines corresponding `argument`s, Ash will consume them correctly.
- This also plays nicely with custom `create function:` usage; your factory function receives the same key/value pairs.

```elixir
# Enable the Scenario DSL in a test module
use AshScenario.Scenario

# Define scenarios
  scenario :my_setup do
    prototype :example_post do
      attr(:title, "Overridden title")
    end
  end

# Run a scenario
{:ok, resources} = AshScenario.run_scenario(__MODULE__, :my_setup, domain: MyApp.Domain)

# Access created resources by their prototype names (atoms)
resources.example_post.title
resources.example_blog.id
```

### Identifiers

- Resource definition metadata uses `ref` as the identifier (e.g., `example_post.ref == :example_post`).
- Earlier examples or code using a metadata field named `name` should be updated to use `ref`.
- This does not affect your domain resource attributes (like a blog's `:name` string); those remain unchanged and are still accessed as struct fields (e.g., `blog.name`).

## API Reference

### Prototype Management

```elixir
# Create prototypes with database persistence (default)
AshScenario.run(prototype_list, opts)
AshScenario.run_all(Module, opts)

# Create prototypes as in-memory structs (no database)
AshScenario.run(prototype_list, strategy: :struct)
AshScenario.run_all(Module, strategy: :struct)

# Run named scenarios
AshScenario.run_scenario(TestModule, :scenario_name, opts)
```

### Introspection

```elixir
# New API
AshScenario.prototypes(Module)         # Get all prototype definitions
AshScenario.prototype(Module, :name)   # Get specific prototype definition
AshScenario.has_prototypes?(Module)    # Check if module has prototypes
AshScenario.prototype_names(Module)    # Get all prototype names
```


### Per-Prototype Overrides

You can override creation behavior for a specific prototype instance via a nested `create` (mirrors module-level `create`):

```elixir
prototypes do
  # Use a specific action just for this instance
  prototype :published_example do
    create action: :publish
    attr :title, "Published Title"
    attr :content, "Body"
    attr :blog_id, :example_blog
  end

  # Or override with a custom function just for this resource
  prototype :factory_post do
    create function: {MyFactory, :create_post_with_tags, ["PREFIX"]}
    attr :title, "Factory Post"
    attr :blog_id, :example_blog
  end
end

# Precedence:
# 1) prototype.create.function (or prototype.function)
# 2) prototype.create.action (or prototype.action)
# 3) module-level create.function
# 4) module-level create.action (default :create)
```

## Clarity Integration

AshScenario ships with an optional `Clarity.Introspector` implementation that
adds a **Prototypes** tab to each Ash resource page inside Clarity. From there
you can run prototypes (database or struct strategy) without leaving the
dashboard.

1. Add the introspector to your Clarity configuration:

   ```elixir
   # config/config.exs or the Clarity umbrella config
   config :my_app, :clarity_introspectors, [
     AshScenario.Clarity.Introspector
   ]
   ```

2. Compile with both `ash_scenario` and `clarity` available. When Clarity is
   running you'll see a new **Prototypes** tab for any resource that defines
   prototypes via `AshScenario.Dsl`.

3. Use the provided buttons to create individual prototypes (database or struct
   strategy) or run the entire set for the resource. Each card also renders a
   sample struct (using `AshScenario.run_all/2` with the `:struct` strategy) so
   you can see the default values that will be generated.

The integration is completely optional—`AshScenario` avoids a direct dependency
on Clarity and only defines the modules when Clarity (and Phoenix LiveView) are
present at compile time.

## Architecture

- **Dependency Graph**: Prototypes are analyzed for dependencies and created in topological order
- **Reference Resolution**: Prototype references (like `:example_blog`) are resolved to actual resource IDs at runtime
- **Registry**: A GenServer maintains the registry of all prototype definitions across modules

## Contributing

### Development Setup

After cloning the repository and installing dependencies:

```bash
# Install dependencies
mix deps.get
```

The project uses `git_hooks` to manage git hooks. The pre-commit hook will automatically format staged Elixir files to ensure consistent code style.

### Code Quality

Before committing, ensure your code passes all quality checks:

```bash
# Run all quality checks
mix check

# Run tests
mix test

# Format code
mix format
```
