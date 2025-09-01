defmodule Blog do
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

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

  resources do
    resource :example_blog,
      name: "Example name"

    resource :tech_blog,
      name: "Tech Blog"
  end
end
