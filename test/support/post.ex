defmodule Post do
  use Ash.Resource,
    domain: Domain

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
    end

    attribute :content, :string do
      public? true
    end
  end

  relationships do
    belongs_to :blog, Blog do
      public? true
    end
  end
end
