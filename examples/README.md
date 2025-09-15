# ash_scenario examples

This lightweight Mix project demonstrates how to define prototypes and scenarios
with [`ash_scenario`](../README.md). It contains:

- `lib/ash_scenario/examples/` – a small multi-tenant Ash domain modelling a
  product launch workspace (organizations, projects, members, tasks, checklist
  items)
- `test/` – executable tests that double as documentation for setting up launch
  scenarios and updating checklist items

## Getting started

```bash
cd examples
mix deps.get
mix test
```

The tests exercise both `AshScenario.run_prototype/3` and the scenario DSL so you
can see how dependency resolution, overrides, and custom creation functions fit
together.
