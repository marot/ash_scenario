defmodule AshScenario.Dsl.Prototype do
  @moduledoc """
  Defines a prototype entity that dynamically accepts attributes and relationships
  based on the containing Ash resource's schema.
  
  This replaces the previous `resources/resource` naming to avoid collisions
  with other Spark/Ash DSLs. The semantics are unchanged.
  """

  defstruct [
    :ref,
    :attributes,
    :values,
    :attrs,
    :attr,
    # Names of attributes marked as virtual (skipped by compile-time validation)
    :virtuals,
    # Per-prototype overrides for creation behavior
    :action,
    :function,
    # Nested create entity (mirrors module-level `create`)
    :create,
    :__identifier__
  ]

  @type t :: %__MODULE__{
          ref: atom(),
          attributes: keyword() | map(),
          values: list() | nil,
          attrs: list() | nil,
          attr: list() | nil,
          virtuals: MapSet.t() | list() | nil,
          action: atom() | nil,
          function:
            ({map(), keyword()} -> {:ok, any()} | {:error, any()})
            | mfa()
            | nil,
          create: AshScenario.Dsl.Create.t() | nil,
          __identifier__: atom()
        }
end

