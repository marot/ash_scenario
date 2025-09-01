defmodule AshScenario.Dsl.Resource do
  @moduledoc """
  Defines a resource entity that dynamically accepts attributes and relationships
  based on the containing Ash resource's schema.
  """

  defstruct [
    :name,
    :attributes,
    :__identifier__
  ]

  @type t :: %__MODULE__{
    name: atom(),
    attributes: keyword() | map(),
    __identifier__: atom()
  }
end