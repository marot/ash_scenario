defmodule AshScenario.Dsl do
  @moduledoc """
  DSL extension for defining resources in Ash resources.
  
  This extension allows resources to define named test data resources with dynamic
  attribute and relationship values based on the resource's schema.
  """

  @resource %Spark.Dsl.Entity{
    name: :resource,
    target: AshScenario.Dsl.Resource,
    args: [:name, {:optional, :attributes}],
    identifier: :name,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the resource"
      ],
      attributes: [
        type: :keyword_list,
        required: false,
        default: [],
        doc: "Attributes and relationships for the resource"
      ]
    ]
  }

  @resources %Spark.Dsl.Section{
    name: :resources,
    describe: "Define named resources for creating test data", 
    entities: [@resource],
    schema: []
  }

  use Spark.Dsl.Extension,
    sections: [@resources],
    transformers: [AshScenario.Dsl.Transformers.ValidateResources]
end