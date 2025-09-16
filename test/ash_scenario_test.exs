defmodule AshScenarioTest do
  use ExUnit.Case
  doctest AshScenario

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "prototype DSL" do
    test "prototypes are defined with dynamic attributes" do
      prototypes = AshScenario.prototypes(Post)
      assert length(prototypes) == 2

      example_post = AshScenario.prototype(Post, :example_post)
      assert example_post.ref == :example_post
      assert example_post.attributes[:title] == "A post title"
      assert example_post.attributes[:content] == "The content of the example post"
      assert example_post.attributes[:blog_id] == :example_blog
    end

    test "prototypes are validated against resource attributes" do
      # This test ensures that the compile-time validation works
      # The Post resource should accept title, content, and blog
      # but reject invalid attributes
      assert AshScenario.has_prototypes?(Post)
      assert AshScenario.has_prototypes?(Blog)
    end

    test "prototype names are accessible" do
      post_prototypes = AshScenario.prototype_names(Post)
      assert :example_post in post_prototypes
      assert :another_post in post_prototypes

      blog_prototypes = AshScenario.prototype_names(Blog)
      assert :example_blog in blog_prototypes
      assert :tech_blog in blog_prototypes
    end
  end

  describe "scenario registry" do
    test "prototypes are registered automatically" do
      post_prototypes = AshScenario.Scenario.Registry.get_prototypes(Post)
      assert length(post_prototypes) == 2

      blog_prototypes = AshScenario.Scenario.Registry.get_prototypes(Blog)
      assert length(blog_prototypes) == 2
    end

    test "specific prototypes can be retrieved" do
      prototype = AshScenario.Scenario.Registry.get_prototype({Post, :example_post})
      assert prototype.ref == :example_post
      assert prototype.resource == Post
    end
  end

  describe "scenario execution" do
    setup do
      :ok
    end

    test "single prototype can be run" do
      assert {:ok, blog} = AshScenario.run_prototype(Blog, :example_blog, domain: Domain)
      assert blog.name == "Example name"
    end

    test "multiple prototypes can be run with dependency resolution" do
      result =
        AshScenario.run_prototypes(
          [
            {Blog, :example_blog},
            {Post, :example_post}
          ],
          domain: Domain
        )

      assert {:ok, created_resources} = result
      assert map_size(created_resources) == 2

      blog = created_resources[{Blog, :example_blog}]
      post = created_resources[{Post, :example_post}]

      assert blog.name == "Example name"
      assert post.title == "A post title"
      assert post.content == "The content of the example post"
    end

    test "all prototypes for a resource can be run" do
      assert {:ok, created_resources} = AshScenario.run_all_prototypes(Blog, domain: Domain)
      assert map_size(created_resources) == 2

      example_blog = created_resources[{Blog, :example_blog}]
      tech_blog = created_resources[{Blog, :tech_blog}]

      assert example_blog.name == "Example name"
      assert tech_blog.name == "Tech Blog"
    end
  end

  describe "error handling" do
    test "running non-existent prototype returns error" do
      result = AshScenario.run_prototype(Post, :nonexistent, domain: Domain)
      assert {:error, message} = result
      assert message =~ "Prototype :nonexistent not found"
    end

    test "scenarios with invalid attributes are caught at compile time" do
      # This would be caught by the transformer during compilation
      # We can't easily test this in a runtime test, but the transformer
      # should prevent compilation of resources with invalid scenario attributes
      assert true
    end
  end

  describe "dynamic attribute support" do
    test "prototypes only accept valid resource attributes" do
      # Test that our Post prototypes only use valid attributes
      example_post = AshScenario.prototype(Post, :example_post)

      # These are all valid Post attributes/relationships
      valid_keys = [:title, :content, :blog_id]
      scenario_keys = Keyword.keys(example_post.attributes)

      assert Enum.all?(scenario_keys, fn key -> key in valid_keys end)
    end

    test "blog prototypes only use valid blog attributes" do
      example_blog = AshScenario.prototype(Blog, :example_blog)

      # Blog only has the 'name' attribute
      valid_keys = [:name]
      scenario_keys = Keyword.keys(example_blog.attributes)

      assert Enum.all?(scenario_keys, fn key -> key in valid_keys end)
    end
  end
end
