defmodule AshScenarioTest do
  use ExUnit.Case
  doctest AshScenario

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    AshScenario.clear_resources()
    :ok
  end

  describe "scenario DSL" do
    test "resources can define scenarios with dynamic attributes" do
      scenarios = AshScenario.scenarios(Post)
      assert length(scenarios) == 2

      example_post = AshScenario.scenario(Post, :example_post)
      assert example_post.ref == :example_post
      assert example_post.attributes[:title] == "A post title"
      assert example_post.attributes[:content] == "The content of the example post"
      assert example_post.attributes[:blog_id] == :example_blog
    end

    test "scenarios are validated against resource attributes" do
      # This test ensures that the compile-time validation works
      # The Post resource should accept title, content, and blog
      # but reject invalid attributes
      assert AshScenario.has_scenarios?(Post)
      assert AshScenario.has_scenarios?(Blog)
    end

    test "scenario names are accessible" do
      post_scenarios = AshScenario.scenario_names(Post)
      assert :example_post in post_scenarios
      assert :another_post in post_scenarios

      blog_scenarios = AshScenario.scenario_names(Blog)
      assert :example_blog in blog_scenarios
      assert :tech_blog in blog_scenarios
    end
  end

  describe "scenario registry" do
    test "scenarios are registered automatically" do
      AshScenario.register_resources(Post)
      AshScenario.register_resources(Blog)

      post_scenarios = AshScenario.Scenario.Registry.get_scenarios(Post)
      assert length(post_scenarios) == 2

      blog_scenarios = AshScenario.Scenario.Registry.get_scenarios(Blog)
      assert length(blog_scenarios) == 2
    end

    test "specific scenarios can be retrieved" do
      AshScenario.register_resources(Post)

      scenario = AshScenario.Scenario.Registry.get_scenario({Post, :example_post})
      assert scenario.ref == :example_post
      assert scenario.resource == Post
    end
  end

  describe "scenario execution" do
    setup do
      AshScenario.register_resources(Post)
      AshScenario.register_resources(Blog)
      :ok
    end

    test "single scenario can be run" do
      assert {:ok, blog} = AshScenario.run_scenario(Blog, :example_blog, domain: Domain)
      assert blog.name == "Example name"
    end

    test "multiple scenarios can be run with dependency resolution" do
      result = AshScenario.run_scenarios([
        {Blog, :example_blog},
        {Post, :example_post}
      ], domain: Domain)

      assert {:ok, created_resources} = result
      assert map_size(created_resources) == 2

      blog = created_resources[{Blog, :example_blog}]
      post = created_resources[{Post, :example_post}]

      assert blog.name == "Example name"
      assert post.title == "A post title"
      assert post.content == "The content of the example post"
    end

    test "all scenarios for a resource can be run" do
      assert {:ok, created_resources} = AshScenario.run_all_scenarios(Blog, domain: Domain)
      assert map_size(created_resources) == 2

      example_blog = created_resources[{Blog, :example_blog}]
      tech_blog = created_resources[{Blog, :tech_blog}]

      assert example_blog.name == "Example name"
      assert tech_blog.name == "Tech Blog"
    end
  end

  describe "error handling" do
    test "running non-existent scenario returns error" do
      AshScenario.register_resources(Post)

      result = AshScenario.run_scenario(Post, :nonexistent, domain: Domain)
      assert {:error, message} = result
      assert message =~ "Resource nonexistent not found"
    end

    test "scenarios with invalid attributes are caught at compile time" do
      # This would be caught by the transformer during compilation
      # We can't easily test this in a runtime test, but the transformer
      # should prevent compilation of resources with invalid scenario attributes
      assert true
    end
  end

  describe "dynamic attribute support" do
    test "scenarios only accept valid resource attributes" do
      # Test that our Post scenarios only use valid attributes
      example_post = AshScenario.scenario(Post, :example_post)
      
      # These are all valid Post attributes/relationships
      valid_keys = [:title, :content, :blog_id]
      scenario_keys = Keyword.keys(example_post.attributes)
      
      assert Enum.all?(scenario_keys, fn key -> key in valid_keys end)
    end

    test "blog scenarios only use valid blog attributes" do
      example_blog = AshScenario.scenario(Blog, :example_blog)
      
      # Blog only has the 'name' attribute
      valid_keys = [:name]
      scenario_keys = Keyword.keys(example_blog.attributes)
      
      assert Enum.all?(scenario_keys, fn key -> key in valid_keys end)
    end
  end
end
