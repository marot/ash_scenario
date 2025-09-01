defmodule AshScenario.Dsl do
  @moduledoc """
  DSL extension for defining resources in Ash resources.

  This extension allows resources to define named test data resources with dynamic
  attribute and relationship values based on the resource's schema.
  """

  @attr %Spark.Dsl.Entity{
    name: :attr,
    target: AshScenario.Dsl.Attr,
    args: [:name, :value],
    identifier: nil,
    schema: [
      name: [type: :atom, required: true],
      value: [type: :any, required: true]
    ]
  }

  @resource %Spark.Dsl.Entity{
    name: :resource,
    target: AshScenario.Dsl.Resource,
    args: [:ref],
    identifier: :ref,
    no_depend_modules: [],
    transform: {__MODULE__, :transform_resource, []},
    schema: [
      ref: [type: :atom, required: true]
    ],
    entities: [
      values: [@attr]
    ]
  }

  @create %Spark.Dsl.Entity{
    name: :create,
    target: AshScenario.Dsl.Create,
    schema: [
      function: [
        type: {:or, [:mfa, {:fun, 2}]},
        required: false,
        default: nil,
        doc: "Optional custom function for creating this resource module's records"
      ],
      action: [
        type: :atom,
        required: false,
        default: :create,
        doc: "Create action name to use when no function is provided"
      ]
    ]
  }

  @resources %Spark.Dsl.Section{
    name: :resources,
    describe: "Define named resources for creating test data",
    entities: [@create, @resource],
    schema: []
  }

  def transform_resource(resource) do
    nested_values =
      (resource.values || resource.attrs || resource.attr || [])
      |> Enum.map(fn %AshScenario.Dsl.Attr{name: name, value: value} -> {name, value} end)

    base_attributes = resource.attributes || []
    attributes = Keyword.merge(base_attributes, nested_values)

    {:ok, %{resource | attributes: attributes}}
  end

  use Spark.Dsl.Extension,
    sections: [@resources],
    transformers: [AshScenario.Dsl.Transformers.ValidateResources]
end
