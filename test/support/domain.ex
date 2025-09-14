defmodule Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    allow_unregistered? true
    resource Blog
    resource Post
    resource Validated
  end
end
