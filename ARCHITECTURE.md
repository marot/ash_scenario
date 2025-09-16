# AshScenario Architecture

## Overview

AshScenario is a testing and data generation framework for Ash resources that provides a declarative way to create test data with automatic dependency resolution. The architecture follows a modular design with clear separation of concerns between DSL definition, execution strategies, and resource creation.

## Core Components

### 1. DSL (Domain Specific Language)

The DSL layer provides the declarative syntax for defining prototypes within Ash resources.

#### Key Modules:
- **`AshScenario.Dsl`** - Main DSL extension that integrates with Ash resources
- **`AshScenario.Dsl.Prototype`** - Defines the structure of individual prototypes
- **`AshScenario.Info`** - Introspection API for accessing DSL-defined prototypes

#### Example Usage:
```elixir
defmodule MyApp.User do
  use Ash.Resource, extensions: [AshScenario.Dsl]

  prototypes do
    prototype :admin_user do
      attr(:name, "Admin")
      attr(:role, :admin)
      attr(:organization_id, :test_org)  # References another prototype
    end
  end
end
```

### 2. Scenario Module

The Scenario module is the core public API for all prototype execution.

#### Key Modules:
- **`AshScenario.Scenario`** - Main entry point with functions like `run/2`, `run_all/2`, `run_scenario/3`
- **`AshScenario.Scenario.Registry`** - Manages prototype registration and dependency resolution
- **`AshScenario.Scenario.Helpers`** - Shared utility functions for attribute resolution and resource tracking

#### Responsibilities:
- Provides the public API surface
- Determines execution strategy from options (`:database` or `:struct`)
- Routes requests to appropriate execution strategies
- Manages the prototype registry

### 3. Executors

The Executor implements a strategy pattern for prototype execution, allowing different behaviors for database persistence vs in-memory struct creation.

#### Core Executor:
- **`AshScenario.Scenario.Executor`** - Central execution engine that:
  - Resolves dependencies between prototypes
  - Manages execution order
  - Handles attribute preparation and resolution
  - Delegates actual resource creation to strategies

#### Strategy Pattern:
The Executor uses a behavior-based strategy pattern with two implementations:

##### DatabaseStrategy (`AshScenario.Scenario.Executor.DatabaseStrategy`)
- Uses `Ash.create/2` for database persistence
- Wraps execution in database transactions for atomicity
- Extracts tenant information for multi-tenant resources
- Returns persisted resources with database-generated IDs

##### StructStrategy (`AshScenario.Scenario.Executor.StructStrategy`)
- Creates in-memory structs without database interaction
- Generates UUIDs for primary keys
- Preserves relationship references as structs (not IDs)
- Ideal for unit tests that don't require persistence

### 4. Public API

The public API provides multiple entry points for different use cases, all routing through a common execution pipeline.

#### API Functions:
- `run/2` - Execute prototypes with specified strategy (`:database` or `:struct`)
- `run_all/2` - Execute all prototypes defined in a resource
- `run_scenario/3` - Execute a named scenario from a test module

#### Strategy Selection:
```elixir
# Database persistence (default)
{:ok, resources} = AshScenario.run(prototypes, strategy: :database)

# In-memory structs
{:ok, resources} = AshScenario.run(prototypes, strategy: :struct)
```

## Data Flow

### 1. Prototype Definition
```
Ash Resource → DSL Extension → Prototype Registration
```

### 2. Execution Flow
```
Public API (Scenario.run/2)
    ↓
Determine strategy from options
    ↓
Executor.execute_prototypes/3
    ↓
Registry.resolve_dependencies/1  [Dependency Resolution]
    ↓
Execute ordered prototypes
    ↓
Strategy.create_resource/3  [DatabaseStrategy or StructStrategy]
    ↓
Return created resources
```

### 3. Dependency Resolution
```
Prototype references (:admin → User)
    ↓
Registry resolves to {Module, :prototype_name}
    ↓
Topological sort based on dependencies
    ↓
Execution in dependency order
```

## Key Design Patterns

### Strategy Pattern
The Executor uses strategies to vary resource creation behavior:
- Strategies implement a common behavior (`@behaviour`)
- Selection happens via the `:strategy` option in the public API
- Each strategy encapsulates its creation logic
- Default strategy is `:database`

### Dependency Injection
Prototypes can reference other prototypes by atom:
- `:org_id` references are resolved to actual created resources
- Dependencies are automatically created in the correct order
- Circular dependencies are detected and prevented

### Builder Pattern
The DSL provides a fluent interface for prototype construction:
- Attributes can be defined incrementally
- Overrides can be applied at runtime
- Custom functions can replace default creation logic

## Extension Points

### Custom Creation Functions
Prototypes can specify custom creation functions:
```elixir
prototypes do
  create function: {MyFactory, :create_user, []}

  prototype :custom_user do
    attr(:name, "Custom")
  end
end
```

### Multitenancy Support
The framework automatically handles multi-tenant resources:
- Detects tenant configuration via Ash multitenancy
- Extracts tenant values from attributes
- Passes tenant context to Ash.create

### Transformers
DSL transformers validate and process prototype definitions:
- **`ValidatePrototypes`** - Ensures prototype validity
- **`RegisterPrototypes`** - Registers prototypes with the registry
