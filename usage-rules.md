# AshScenario Usage Rules

Reusable test data generation for Ash applications with dependency resolution and scenario composition.

## Understanding AshScenario

AshScenario provides two complementary approaches for test data:

1. **Prototype Definitions**: Reusable data templates defined in Ash resources using a DSL
2. **Test Scenarios**: Override and compose prototypes in test modules with named scenarios

Prototypes are created automatically in dependency order based on relationships.

## Prototype Definitions

### Basic Setup

Always add the DSL extension to your Ash resource before defining prototypes:

```elixir
defmodule Blog do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshScenario.Dsl]  # Required

  # ... attributes, actions, etc. ...

  prototypes do
    prototype :example_blog do
      attr :name, "Example Blog"
    end

    prototype :tech_blog do
      attr :name, "Tech Blog"
    end
  end
end
```

### Prototype References

Use atom symbols to reference other prototypes in relationships:

```elixir
prototypes do
  prototype :example_post do
    attr :title, "A post title"
    attr :content, "Post content"
    # References the example_blog prototype
    attr :blog_id, :example_blog
  end
end
```

**Important**: Only relationship attributes (like `blog_id`) resolve references. Other atoms are preserved as-is:

```elixir
prototype :my_post do
  attr :title, "Title"
  attr :status, :draft        # Preserved as atom
  attr :blog_id, :example_blog # Resolved to blog's actual ID
end
```

### Custom Creation Functions

For complex setup logic, specify custom functions instead of default Ash actions:

```elixir
prototypes do
  create function: {MyFactory, :create_blog, []}

  prototype :factory_blog do
    attr :name, "Factory Blog"
  end
end
```

**Custom function requirements**:
- Accept `(resolved_attributes, opts)` parameters
- Return `{:ok, created_resource}` or `{:error, reason}`
- Handle resolved attributes where references are already converted to IDs

```elixir
def create_blog(resolved_attributes, opts) do
  # All relationship references are already resolved to IDs
  # resolved_attributes = %{name: "Factory Blog", some_id: "uuid-string"}
  
  # Your custom creation logic
  {:ok, created_resource}
end
```

### Automatic Dependency Resolution

**All APIs automatically resolve dependencies**: Both the direct API and test scenarios pull in all required dependencies automatically.

```elixir
# Only specify what you want - dependencies are created automatically!
{:ok, resources} = AshScenario.run([
  {Post, :example_post}  # References :example_blog in blog_id
], domain: MyApp.Domain)

# Both blog and post are created automatically
blog = resources[{Blog, :example_blog}]  # Dependency created automatically
post = resources[{Post, :example_post}]   # Explicitly requested
assert post.blog_id == blog.id
```

**Single prototype dependency resolution**:

```elixir
# Single prototype also pulls in all dependencies
{:ok, resources} = AshScenario.run([{Post, :example_post}], domain: MyApp.Domain)
post = resources[{Post, :example_post}]
# The referenced blog was created automatically
assert is_binary(post.blog_id)  # Resolved to actual UUID
```

**Multi-level dependencies**:

```elixir
# Comment -> Post -> Blog chain resolved automatically
{:ok, resources} = AshScenario.run([
  {Comment, :example_comment}  # Only specify the leaf node
], domain: MyApp.Domain)

# All dependencies created in correct order:
comment = resources[{Comment, :example_comment}]
post = resources[{Post, :example_post}]     # Auto-created
blog = resources[{Blog, :example_blog}]     # Auto-created
```

## Test Scenarios

### Basic Scenario Setup

Add scenario support to test modules:

```elixir
defmodule MyTest do
  use ExUnit.Case
  use AshScenario.Scenario  # Required for scenarios

  scenario :basic_setup do
    example_blog do
      name "Custom blog name"
    end
    
    example_post do
      title "Custom post title" 
    end
  end

  test "my test" do
    {:ok, resources} = AshScenario.run_scenario(__MODULE__, :basic_setup)
    assert resources.example_blog.name == "Custom blog name"
  end
end
```

### Scenario Extension

Build hierarchical scenarios using `extends`:

```elixir
scenario :base_setup do
  example_blog do
    name "Base Blog"
  end
  
  example_post do
    title "Base Post"
    content "Base content"
  end
end

scenario :extended_setup, extends: :base_setup do
  example_post do
    title "Extended Post"  # Overrides title
    # content is inherited as "Base content"
  end
  
  another_post do  # Adds new prototype
    title "Additional post"
  end
end
```

**Extension rules**:
- Child scenarios inherit all prototypes from parent
- Child attributes override parent attributes for same prototype
- Child scenarios can add new prototypes
- Multiple levels of extension are supported

## API Usage Patterns

### Strategy Options

```elixir
# Create with database persistence (default)
{:ok, resources} = AshScenario.run(prototypes, strategy: :database)

# Create as in-memory structs without persistence
{:ok, resources} = AshScenario.run(prototypes, strategy: :struct)
```

### Single Prototypes

```elixir
# Create one prototype (returns a map)
{:ok, resources} = AshScenario.run([{Blog, :example_blog}], domain: MyApp.Domain)
blog = resources[{Blog, :example_blog}]
```

### Multiple Prototypes

```elixir
# Create specific prototypes with dependencies
{:ok, resources} = AshScenario.run([
  {Blog, :example_blog},
  {Post, :example_post}
], domain: MyApp.Domain)
```

### All Prototypes from a Module

```elixir
# Create all defined prototypes in a module
{:ok, resources} = AshScenario.run_all(Blog, domain: MyApp.Domain)
```

### Domain Inference

If not provided, domain is inferred from the resource module:

```elixir
# Domain inferred from Blog module
{:ok, resources} = AshScenario.run([{Blog, :example_blog}])
blog = resources[{Blog, :example_blog}]

# Explicitly specify domain
{:ok, resources} = AshScenario.run([{Blog, :example_blog}], domain: MyApp.Domain)
```

## Common Patterns

### Factory Integration

Integrate with existing factory functions:

```elixir
defmodule MyFactory do
  def create_user_with_profile(attrs, _opts) do
    user = create_user(attrs)
    profile = create_profile_for_user(user)
    {:ok, %{user | profile: profile}}
  end
end

prototypes do
  create function: {MyFactory, :create_user_with_profile, []}

  prototype :admin_user do
    attr :email, "admin@example.com"
    attr :role, :admin
  end
end
```

### Complex Dependencies

Handle multi-level dependencies:

```elixir
# User -> Blog -> Post chain
prototypes do  
  prototype :author do
    attr :name, "John Doe"
  end
  
  prototype :personal_blog do
    attr :name, "John's Blog"
    attr :user_id, :author
  end
  
  prototype :featured_post do
    attr :title, "My Featured Post"
    # Automatically resolves the chain
    attr :blog_id, :personal_blog
  end
end
```

### Test Data Variations

Create multiple variations of the same prototype:

```elixir
prototypes do
  prototype :draft_post do
    attr :title, "Draft Post"
    attr :status, :draft
    attr :blog_id, :example_blog
  end
  
  prototype :published_post do
    attr :title, "Published Post"
    attr :status, :published
    attr :blog_id, :example_blog
  end
end
```

## Best Practices

1. **Always use the DSL extension**: Add `AshScenario.Dsl` to resources before defining prototypes
2. **Use meaningful names**: Prototype names should be descriptive (`example_blog`, not `blog1`)
3. **Group related prototypes**: Define prototypes in the same module as the Ash resource when possible
4. **Prefer prototype references**: Use `:prototype_name` atoms for relationships instead of hardcoded IDs
5. **Trust automatic dependency resolution**: Only specify the prototypes you actually need - dependencies are handled automatically
6. **Keep scenarios focused**: Each scenario should represent a specific test context
7. **Use extends for variants**: Build scenario hierarchies instead of duplicating definitions
8. **Custom functions for complex logic**: Use custom functions when default Ash actions aren't sufficient
9. **Explicit domains when needed**: Specify domain explicitly if inference doesn't work
10. **Use virtual attributes for action args**: Mark non-persisted inputs (e.g., `password`) with `virtual: true`

### Virtual Attributes Example

```elixir
prototypes do
  # create action defines arguments :password and :password_confirmation
  create action: :register

  prototype :admin_user do
    attr :email, "admin@example.com"
    attr :password, "s3cret", virtual: true
    attr :password_confirmation, "s3cret", virtual: true
  end
end
```

### Per-Prototype Overrides

You can override the action/function for a single prototype instance using a nested `create`:

```elixir
prototypes do
  # Use a custom action just for this instance
  prototype :published_example do
    create action: :publish
    attr :title, "Published Title"
    attr :content, "Body"
    attr :blog_id, :example_blog
  end

  # Or a custom function only for this instance
  prototype :factory_post do
    create function: {MyFactory, :create_post_with_tags, ["PREFIX"]}
    attr :title, "Factory Post"
    attr :blog_id, :example_blog
  end
end

# Precedence
# 1) prototype.create.function
# 2) prototype.create.action
# 3) module-level create.function
# 4) module-level create.action (default :create)
```

## Common Issues

### Prototype Not Found
```elixir
# Error: Prototype :missing_blog not found
prototype :my_post do
  attr :blog_id, :missing_blog
end

# Fix: Ensure referenced prototype exists
prototypes do
  prototype :example_blog do
    attr :name, "Blog"
  end
  prototype :my_post do
    attr :blog_id, :example_blog
  end
end
```

### Circular Dependencies
```elixir
# Error: Circular reference between prototypes
prototype :post_a do
  attr :related_post_id, :post_b
end
prototype :post_b do
  attr :related_post_id, :post_a
end

# Fix: Use nil or remove circular references
prototype :post_a do
  attr :related_post_id, nil
end
prototype :post_b do
  attr :related_post_id, :post_a
end
```

### Custom Function Errors
```elixir
# Error: Custom function must return {:ok, record} or {:error, reason}
def bad_function(attrs, _opts) do
  create_record(attrs)  # Returns record directly
end

# Fix: Wrap in proper tuple
def good_function(attrs, _opts) do
  record = create_record(attrs)
  {:ok, record}
end
```
