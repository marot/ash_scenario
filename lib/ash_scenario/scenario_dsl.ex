defmodule AshScenario.ScenarioDsl do
  @moduledoc """
  Spark DSL extension for defining test scenarios with prototype overrides.
  """

  @attr %Spark.Dsl.Entity{
    name: :attr,
    target: AshScenario.ScenarioDsl.AttributeOverride,
    args: [:name, :value],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The attribute name to override"
      ],
      value: [
        type: :any,
        required: true,
        doc: "The value to set for the attribute"
      ]
    ]
  }

  @prototype %Spark.Dsl.Entity{
    name: :prototype,
    target: AshScenario.ScenarioDsl.PrototypeOverride,
    args: [:ref],
    schema: [
      ref: [
        type: {:or, [:atom, {:tuple, [:atom, :atom]}]},
        required: true,
        doc: "Reference to the prototype (e.g., :post or {Post, :published})"
      ]
    ],
    entities: [
      attributes: [@attr]
    ]
  }

  @scenario %Spark.Dsl.Entity{
    name: :scenario,
    target: AshScenario.ScenarioDsl.Scenario,
    args: [:name],
    identifier: :name,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Unique name for the scenario"
      ],
      extends: [
        type: {:or, [:atom, {:list, :atom}]},
        required: false,
        doc: "Parent scenario(s) to inherit from"
      ]
    ],
    entities: [
      prototypes: [@prototype]
    ]
  }

  @scenarios %Spark.Dsl.Section{
    name: :scenarios,
    describe: "Define test scenarios with prototype overrides",
    entities: [@scenario],
    top_level?: false,
    imports: []
  }

  use Spark.Dsl.Extension,
    sections: [@scenarios],
    transformers: [
      AshScenario.ScenarioDsl.Transformers.ResolveInheritance
    ]
end
