defmodule AshScenario.Dsl do
  @moduledoc """
  DSL extension for defining resources in Ash resources.
  
  This extension allows resources to define named test data resources with dynamic
  attribute and relationship values based on the resource's schema.
  """

  @resource %Spark.Dsl.Entity{
    name: :resource,
    target: AshScenario.Dsl.Resource,
    args: [:ref],
    identifier: :ref,
    no_depend_modules: [:function],
    transform: {__MODULE__, :transform_resource, []},
    schema: [
      function: [
        type: {:or, [:mfa, {:fun, 2}]},
        required: false,
        default: nil,
        doc: "Optional custom function for creating the resource. Can be {module, function, extra_args} or a 2-arity function"
      ]
    ]
  }

  @resources %Spark.Dsl.Section{
    name: :resources,
    describe: "Define named resources for creating test data", 
    entities: [@resource],
    schema: []
  }

  def transform_resource(resource) do
    # Extract all fields except ref, function, and internal fields as attributes
    reserved_keys = [:ref, :function, :__identifier__, :attributes]
    struct_map = Map.from_struct(resource)
    
    # Get all fields that should be attributes
    attributes = 
      struct_map
      |> Map.drop(reserved_keys)
      |> Enum.filter(fn {_key, value} -> value != nil end)
      |> Enum.to_list()
    
    %{resource | attributes: attributes}
  end

  use Spark.Dsl.Extension,
    sections: [@resources],
    transformers: [AshScenario.Dsl.Transformers.ValidateResources]
end