defmodule AshScenario.Dsl.Attr do
  @moduledoc """
  Represents a single attribute entry within a resource DSL definition.
  """

  defstruct [
    :name,
    :value,
    :__identifier__
  ]

  @type t :: %__MODULE__{
          name: atom(),
          value: any(),
          __identifier__: atom() | nil
        }
end

