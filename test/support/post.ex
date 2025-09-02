defmodule Post do
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
    end

    attribute :content, :string do
      public? true
    end

    attribute :status, :string do
      public? true
      default "draft"
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
      accept [:title, :content, :blog_id]
    end

    create :publish do
      accept [:title, :content, :blog_id]
      change set_attribute(:status, "published")
    end
  end

  prototypes do
    prototype :example_post do
      attr :title, "A post title"
      attr :content, "The content of the example post"
      attr :blog_id, :example_blog
    end

    prototype :another_post do
      attr :title, "Another post title"
      attr :content, "Different content"
      attr :blog_id, :example_blog
    end
  end
end
