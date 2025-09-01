# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-XX

### Added
- Initial release of AshScenario
- Resource definitions DSL for defining reusable test data in Ash resources
- Test scenarios DSL for overriding attributes in test modules
- Scenario extension/inheritance with `extends` option
- Automatic dependency resolution and topological sorting
- Reference resolution (`:resource_name` ’ actual IDs)
- Registry system for resource management
- Comprehensive test coverage
- Backward compatibility with "scenario" terminology

### Features
- `use AshScenario.Dsl` - Add resource definitions to Ash resources
- `use AshScenario.Scenario` - Add scenario definitions to test modules
- `AshScenario.run_resource/3` - Create single resources
- `AshScenario.run_resources/2` - Create multiple resources with dependency resolution
- `AshScenario.Scenario.run/3` - Execute named scenarios from test modules