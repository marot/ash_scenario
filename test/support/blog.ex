defmodule Blog do
  use Ash.Resource,
    domain: Domain

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name]
    end
  end
end
