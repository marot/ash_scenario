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

  prototypes do
    prototype :example_blog do
      attr :name, "Example name"
    end

    prototype :tech_blog do
      attr :name, "Tech Blog"
    end
  end
end
