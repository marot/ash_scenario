defmodule AshScenario.Dsl.Actor do
  @moduledoc """
  Represents an actor entity within a prototype definition.

  The actor specifies which user (or other entity) should act as the actor
  when creating the resource, for authorization purposes.
  """

  defstruct [:value, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          value: atom() | {module(), atom()}
        }
end
