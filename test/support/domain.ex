defmodule Domain do
  use Ash.Domain

  resources do
    allow_unregistered? true
    resource Blog
    resource Post
  end
end
