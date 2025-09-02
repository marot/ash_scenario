defmodule Domain do
  use Ash.Domain

  resources do
    allow_unregistered? true
    resource Blog
    resource Post
    resource Validated
  end
end
