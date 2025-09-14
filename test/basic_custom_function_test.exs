defmodule AshScenario.BasicCustomFunctionTest do
  use ExUnit.Case

  # Test support module for custom functions
  defmodule TestFactory do
    def create_blog(attributes, _opts) do
      blog = %Blog{
        id: Ash.UUID.generate(),
        name: attributes[:name] || "Default Blog"
      }

      {:ok, blog}
    end

    def create_post(attributes, _opts) do
      post = %Post{
        id: Ash.UUID.generate(),
        title: attributes[:title] || "Default Title",
        content: attributes[:content] || "Default Content",
        blog_id: attributes[:blog_id],
        status: attributes[:status] || "draft"
      }

      {:ok, post}
    end
  end

  # Test resource with custom functions using working DSL syntax
  defmodule CustomBlog do
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
      create function: {TestFactory, :create_blog, []}

      prototype :factory_blog do
        attr(:name, "Factory Blog")
      end
    end
  end

  defmodule CustomPost do
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
        accept [:title, :content, :blog_id, :status]
      end
    end

    prototypes do
      create function: {TestFactory, :create_post, []}

      prototype :factory_post do
        attr(:title, "Factory Post")
        attr(:content, "Factory Content")
        attr(:status, "published")
        attr(:blog_id, :factory_blog)
      end
    end
  end

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    AshScenario.clear_prototypes()
    AshScenario.register_prototypes(CustomBlog)
    AshScenario.register_prototypes(CustomPost)
    :ok
  end

  describe "basic custom function support" do
    test "custom function creates prototype correctly" do
      {:ok, blog} = AshScenario.run_prototype(CustomBlog, :factory_blog, domain: Domain)

      assert blog.name == "Factory Blog"
      assert blog.id != nil
    end

    test "custom function with dependency resolution" do
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {CustomBlog, :factory_blog},
            {CustomPost, :factory_post}
          ],
          domain: Domain
        )

      blog = resources[{CustomBlog, :factory_blog}]
      post = resources[{CustomPost, :factory_post}]

      assert blog.name == "Factory Blog"
      assert post.title == "Factory Post"
      # String attribute preserved
      assert post.status == "published"
      # Reference resolved to actual ID
      assert post.blog_id == blog.id
    end

    test "hardened relationship resolution preserves non-relationship atoms" do
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {CustomBlog, :factory_blog},
            {CustomPost, :factory_post}
          ],
          domain: Domain
        )

      post = resources[{CustomPost, :factory_post}]

      # blog_id should be resolved because it's a relationship attribute
      # UUID string
      assert is_binary(post.blog_id)

      # status should remain as string because it's not a relationship attribute
      assert post.status == "published"
      assert is_binary(post.status)
    end
  end
end
