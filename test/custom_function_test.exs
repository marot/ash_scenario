defmodule AshScenario.CustomFunctionTest do
  use ExUnit.Case

  # Test support module for custom functions
  defmodule TestFactory do
    def create_blog(attributes, _opts) do
      blog =
        struct!(
          AshScenario.CustomFunctionTest.CustomBlog,
          id: Ash.UUID.generate(),
          name: attributes[:name] || "Default Blog"
        )

      {:ok, blog}
    end

    def create_post(attributes, _opts) do
      post =
        struct!(
          AshScenario.CustomFunctionTest.CustomPost,
          id: Ash.UUID.generate(),
          title: attributes[:title] || "Default Title",
          content: attributes[:content] || "Default Content",
          blog_id: attributes[:blog_id],
          status: attributes[:status] || :draft
        )

      {:ok, post}
    end

    def create_post_with_extra_args(attributes, _opts, prefix) do
      post =
        struct!(
          AshScenario.CustomFunctionTest.PrefixedPost,
          id: Ash.UUID.generate(),
          title: "#{prefix}: #{attributes[:title]}",
          blog_id: attributes[:blog_id]
        )

      {:ok, post}
    end

    def failing_function(_attributes, _opts) do
      {:error, "This function always fails"}
    end
  end

  # Test resource with custom functions
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

  defmodule CustomBlogAnon do
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
      create function: fn attrs, _opts ->
               {:ok, %Blog{id: Ash.UUID.generate(), name: attrs[:name]}}
             end

      prototype :anonymous_blog do
        attr(:name, "Anonymous Blog")
      end
    end
  end

  defmodule CustomBlogFail do
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
      create function: {TestFactory, :failing_function, []}

      prototype :failing_blog do
        attr(:name, "Failing Blog")
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
      belongs_to :blog, CustomBlog do
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
        attr(:status, :published)
        attr(:blog_id, :factory_blog)
      end
    end
  end

  defmodule PrefixedPost do
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
      belongs_to :blog, CustomBlog do
        public? true
      end
    end

    actions do
      defaults [:read]

      create :create do
        accept [:title, :blog_id]
      end
    end

    prototypes do
      create function: {TestFactory, :create_post_with_extra_args, ["PREFIX"]}

      prototype :prefixed_post do
        attr(:title, "Prefixed Post")
        attr(:blog_id, :factory_blog)
      end
    end
  end

  defmodule RegularPost do
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
    end

    relationships do
      belongs_to :blog, CustomBlog do
        public? true
      end
    end

    actions do
      defaults [:read]

      create :create do
        accept [:title, :content, :blog_id]
      end
    end

    prototypes do
      # No create function: uses default Ash.create :create
      prototype :regular_post do
        attr(:title, "Regular Post")
        attr(:content, "Regular Content")
        attr(:blog_id, :factory_blog)
      end
    end
  end

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "custom function support" do
    test "MFA custom function creates prototype correctly" do
      {:ok, blog} = AshScenario.run_prototype(CustomBlog, :factory_blog, domain: Domain)

      assert blog.name == "Factory Blog"
      assert blog.id != nil
    end

    test "anonymous function creates prototype correctly" do
      {:ok, blog} = AshScenario.run_prototype(CustomBlogAnon, :anonymous_blog, domain: Domain)

      assert blog.name == "Anonymous Blog"
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
      # Preserved as atom
      assert post.status == :published
      # Resolved to actual ID
      assert post.blog_id == blog.id
    end

    test "custom function with extra arguments" do
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {CustomBlog, :factory_blog},
            {PrefixedPost, :prefixed_post}
          ],
          domain: Domain
        )

      post = resources[{PrefixedPost, :prefixed_post}]

      assert post.title == "PREFIX: Prefixed Post"
      assert post.blog_id != nil
    end

    test "error handling for failing custom function" do
      {:error, message} = AshScenario.run_prototype(CustomBlogFail, :failing_blog, domain: Domain)

      assert message =~ "Failed to create"
      assert message =~ "with custom function"
      assert message =~ "This function always fails"
    end

    test "comparison between custom function and regular creation" do
      # Test that regular resources still work alongside custom function resources
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {CustomBlog, :factory_blog},
            # Uses default Ash.create
            {RegularPost, :regular_post},
            # Uses custom function
            {CustomPost, :factory_post}
          ],
          domain: Domain
        )

      blog = resources[{CustomBlog, :factory_blog}]
      regular_post = resources[{RegularPost, :regular_post}]
      factory_post = resources[{CustomPost, :factory_post}]

      # Both posts should reference the same blog
      assert regular_post.blog_id == blog.id
      assert factory_post.blog_id == blog.id

      # Regular post uses default Ash creation
      assert regular_post.title == "Regular Post"

      # Factory post uses custom function
      assert factory_post.title == "Factory Post"
    end
  end

  describe "hardened relationship resolution" do
    test "only relationship attributes are resolved, not other atoms" do
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

      # status should remain as atom because it's not a relationship attribute
      assert post.status == :published
      assert is_atom(post.status)
    end

    test "atoms that don't match prototype names are preserved" do
      # Test with a status that doesn't match any resource name
      {:ok, post} = AshScenario.run_prototype(CustomPost, :factory_post, domain: Domain)

      # :published doesn't match any resource name, should be preserved as atom
      assert post.status == :published
    end
  end

  describe "scenario integration" do
    use AshScenario.Scenario

    scenario :custom_function_scenario do
      prototype :factory_blog do
        attr(:name, "Scenario Blog")
      end

      prototype :factory_post do
        attr(:title, "Scenario Post")
        # Should remain as atom
        attr(:status, :draft)
      end
    end

    test "scenarios work with custom functions" do
      {:ok, resources} =
        AshScenario.Scenario.run(__MODULE__, :custom_function_scenario, domain: Domain)

      assert resources.factory_blog.name == "Scenario Blog"
      assert resources.factory_post.title == "Scenario Post"
      assert resources.factory_post.status == :draft
      assert resources.factory_post.blog_id == resources.factory_blog.id
    end
  end
end
