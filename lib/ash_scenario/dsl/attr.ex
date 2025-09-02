defmodule AshScenario.Dsl.Attr do
  @moduledoc """
  Represents a single attribute entry within a prototype DSL definition.
  """

  defstruct [
    :name,
    :value,
    # When true, skip compile-time validation against the resource schema
    # and pass this key/value through to the create action as an argument.
    # Useful for virtual inputs like passwords that are not stored attributes.
    :virtual,
    :__identifier__
  ]

  @type t :: %__MODULE__{
          name: atom(),
          value: any(),
          virtual: boolean() | nil,
          __identifier__: atom() | nil
        }
end
