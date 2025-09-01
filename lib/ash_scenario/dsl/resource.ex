defmodule AshScenario.Dsl.Resource do
  @moduledoc """
  Defines a resource entity that dynamically accepts attributes and relationships
  based on the containing Ash resource's schema.
  """

  defstruct [
    :ref,
    :attributes,
    :values,
    :attrs,
    :attr,
    :__identifier__
  ]

  @type t :: %__MODULE__{
    ref: atom(),
    attributes: keyword() | map(),
    values: list() | nil,
    attrs: list() | nil,
    attr: list() | nil,
    __identifier__: atom()
  }
end
