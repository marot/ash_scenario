defmodule AshScenario.Dsl.Create do
  @moduledoc """
  Configure how records for a given Ash resource module are created.

  - If `function` is provided, it is used with signature `(attributes, opts)`.
  - Otherwise, uses the specified `action` (defaults to `:create`).
  """

  defstruct [
    :function,
    :action,
    :__identifier__
  ]

  @type t :: %__MODULE__{
          function: ({map(), keyword()} -> {:ok, any()} | {:error, any()}) | mfa() | nil,
          action: atom() | nil,
          __identifier__: atom() | nil
        }
end

