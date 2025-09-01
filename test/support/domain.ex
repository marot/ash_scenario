defmodule Domain do
  use Ash.Domain

  resources do
    resource Blog
    resource Post
  end
end
