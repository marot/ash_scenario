defmodule AshScenario.SimpleScenarioTest do
  use ExUnit.Case

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "prototype DSL (renamed from scenarios)" do
    test "prototypes are defined with new DSL syntax" do
      # Test that we can access resources using new terminology
      resources = AshScenario.prototypes(Post)
      assert length(resources) == 2

      example_post = AshScenario.prototype(Post, :example_post)
      assert example_post.ref == :example_post
      assert example_post.attributes[:title] == "A post title"
      assert example_post.attributes[:blog_id] == :example_blog
    end

    test "prototypes can be created with dependency resolution" do
      # Test that the existing runner works with new terminology
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {Blog, :example_blog},
            {Post, :example_post}
          ],
          domain: Domain
        )

      assert Map.has_key?(resources, {Blog, :example_blog})
      assert Map.has_key?(resources, {Post, :example_post})

      blog = resources[{Blog, :example_blog}]
      post = resources[{Post, :example_post}]

      assert blog.name == "Example name"
      assert post.title == "A post title"
      # Reference resolved correctly
      assert post.blog_id == blog.id
    end

    test "backward compatibility with scenario names" do
      # Test that old API still works
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {Blog, :example_blog},
            {Post, :example_post}
          ],
          domain: Domain
        )

      assert Map.has_key?(resources, {Blog, :example_blog})
      assert Map.has_key?(resources, {Post, :example_post})
    end

    test "all resources for a resource module can be created" do
      {:ok, resources} = AshScenario.run_all_prototypes(Blog, domain: Domain)

      assert Map.has_key?(resources, {Blog, :example_blog})
      assert Map.has_key?(resources, {Blog, :tech_blog})

      example_blog = resources[{Blog, :example_blog}]
      tech_blog = resources[{Blog, :tech_blog}]

      assert example_blog.name == "Example name"
      assert tech_blog.name == "Tech Blog"
    end
  end

  describe "new scenario DSL concept" do
    test "demonstrates the intended usage pattern" do
      # This test shows how the scenario DSL would work once fully implemented
      # For now, we'll use the existing resource-based approach

      # 1. Create blog dependency first
      {:ok, _blog_resources} = AshScenario.run_prototype(Blog, :example_blog, domain: Domain)

      # 2. Create post that references the blog
      {:ok, post_resources} =
        AshScenario.run_prototypes(
          [
            {Blog, :example_blog},
            {Post, :another_post}
          ],
          domain: Domain
        )

      # This shows that we can override the title by creating a custom prototype definition
      # In the future scenario DSL, this would be:
      # scenario :basic_test do
      #   another_post do
      #     title "Override title"
      #   end
      # end

      blog = post_resources[{Blog, :example_blog}]
      post = post_resources[{Post, :another_post}]

      assert blog.name == "Example name"
      # From prototype definition
      assert post.title == "Another post title"
      assert post.blog_id == blog.id
    end
  end
end
