defmodule AshScenario.Dsl do
  @moduledoc """
  DSL extension for defining prototypes in Ash resources.

  This extension allows Ash resources to define named test data prototypes with dynamic
  attribute and relationship values based on the resource's schema.
  """

  @attr %Spark.Dsl.Entity{
    name: :attr,
    target: AshScenario.Dsl.Attr,
    args: [:name, :value],
    identifier: nil,
    schema: [
      name: [type: :atom, required: true],
      value: [type: :any, required: true],
      virtual: [
        type: :boolean,
        required: false,
        default: false,
        doc: "Allow keys not defined as attributes/relationships; passed as create arguments"
      ]
    ]
  }

  @actor %Spark.Dsl.Entity{
    name: :actor,
    target: AshScenario.Dsl.Actor,
    args: [:value],
    identifier: nil,
    schema: [
      value: [
        type: {:or, [:atom, {:tuple, [:atom, :atom]}]},
        required: true,
        doc:
          "Actor prototype reference for authorization (e.g., :admin_user or {User, :admin_user})"
      ]
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

  @prototype %Spark.Dsl.Entity{
    name: :prototype,
    target: AshScenario.Dsl.Prototype,
    args: [:ref],
    identifier: :ref,
    no_depend_modules: [],
    transform: {__MODULE__, :transform_prototype, []},
    schema: [
      ref: [type: :atom, required: true],
      action: [
        type: :atom,
        required: false,
        doc: "Override the create action for this specific prototype"
      ],
      function: [
        type: {:or, [:mfa, {:fun, 2}]},
        required: false,
        doc: "Override the creation function for this specific prototype"
      ]
    ],
    entities: [
      values: [@attr],
      actor: [@actor],
      create: [@create]
    ]
  }

  @prototypes %Spark.Dsl.Section{
    name: :prototypes,
    describe: "Define named prototypes for creating test data",
    entities: [@create, @prototype],
    schema: []
  }

  def transform_prototype(prototype) do
    attr_entities = prototype.values || prototype.attrs || prototype.attr || []

    nested_values =
      attr_entities
      |> Enum.map(fn %AshScenario.Dsl.Attr{name: name, value: value} -> {name, value} end)

    base_attributes = prototype.attributes || []
    attributes = Keyword.merge(base_attributes, nested_values)

    # Extract actor from actor entity
    actor_value =
      case Map.get(prototype, :actor) do
        [%AshScenario.Dsl.Actor{value: value} | _] -> value
        %AshScenario.Dsl.Actor{value: value} -> value
        _ -> nil
      end

    virtuals =
      attr_entities
      |> Enum.filter(& &1.virtual)
      |> Enum.map(& &1.name)
      |> MapSet.new()

    # If a nested `create` entity is present, map it to action/function
    {action_override, function_override} =
      case Map.get(prototype, :create) do
        [%AshScenario.Dsl.Create{action: act, function: fun} | _] -> {act, fun}
        %AshScenario.Dsl.Create{action: act, function: fun} -> {act, fun}
        _ -> {nil, nil}
      end

    # Preserve explicit per-prototype schema overrides if provided directly
    final_action = Map.get(prototype, :action) || action_override
    final_function = Map.get(prototype, :function) || function_override

    {:ok,
     %{
       prototype
       | attributes: attributes,
         virtuals: virtuals,
         actor: actor_value,
         action: final_action,
         function: final_function
     }}
  end

  use Spark.Dsl.Extension,
    sections: [@prototypes],
    transformers: [AshScenario.Dsl.Transformers.ValidatePrototypes]
end
