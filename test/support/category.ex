defmodule Category do
  @moduledoc false
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      public? true
    end
  end

  relationships do
    belongs_to :blog, Blog do
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :blog_id]
    end
  end

  prototypes do
    prototype :tech_category do
      attr(:name, "Tech")
      attr(:blog_id, :example_blog)
    end

    prototype :lifestyle_category do
      attr(:name, "Lifestyle")
      attr(:blog_id, :example_blog)
    end
  end
end
