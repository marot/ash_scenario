defmodule FeaturedPost do
  @moduledoc false
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
    end
  end

  relationships do
    belongs_to :blog, Blog do
      public? true
    end

    belongs_to :primary_category, Category do
      public? true
    end

    belongs_to :secondary_category, Category do
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title, :blog_id, :primary_category_id, :secondary_category_id]
    end
  end

  prototypes do
    prototype :featured_post do
      attr(:title, "Featured")
      attr(:blog_id, :example_blog)
      attr(:primary_category_id, :tech_category)
      attr(:secondary_category_id, :lifestyle_category)
    end
  end
end
