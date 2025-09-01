# Overview

Ash scenario allows you to define test data for your application. It can be used for tests, staging environments, and more.

## Scenario definition
Scenarios are defined on top of resources.
- The name of a test resource
- The default attributes
- The default relationships
- The actor creating it

## Scenario instantiation
When instantiating a scenario, the user can specify the resource name to pull in the defaults.
The user can specify which attributes and relationships to override.


```elixir
defmodule Blog do
  use Ash.Resource,
    domain: Domain

  attributes do
    uuid_primary_key :id
    attribute :name, :string do
      public? true
    end
  end
end

defmodule Post do
  use Ash.Resource,
    domain: Domain

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
end
```

When creating a resource instance, the scenario will automatically create the necessary dependencies.

Who is the user creating the scenario?
Allow specifying the actor.

## A scenario basically builds a directed acyclic graph (DAG)


## State snapshots
When creating scenarios, only the necessary changes are created.

Or the user can decide to re-create the entire state.

Or use tracing, audit logs, or similar to determine if a resource is dirty?

## State cleanup
What should be cleaned up?

## Architecture
Scenarios are created in parallel where possible.

## Multi tenancy
How is this supported?
