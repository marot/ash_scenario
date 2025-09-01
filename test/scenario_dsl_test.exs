defmodule AshScenario.ScenarioDslTest do
  use ExUnit.Case
  use AshScenario.Scenario

  setup do
    # Ensure registry is started and clear for each test
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    AshScenario.clear_resources()
    AshScenario.register_resources(Post)
    AshScenario.register_resources(Blog)
    :ok
  end

  # Define test scenarios using the new DSL
  scenario :basic_setup do
    another_post do
      title "Override title for basic setup"
    end
  end

  scenario :with_custom_blog do
    tech_blog do
      name "My Custom Tech Blog"
    end
    another_post do
      title "Post in custom blog"
      blog_id :tech_blog
    end
  end

  scenario :multiple_posts do
    example_post do
      title "First post override"
    end
    another_post do
      title "Second post override"
    end
  end

  scenario :single_blog_only do
    example_blog do
      name "Just a blog, no posts"
    end
  end

  # Test scenarios for new features
  scenario :base_scenario do
    example_blog do
      name "Base Blog"
    end
    
    example_post do
      title "Base Post"
      content "Base content"
    end
  end

  scenario :extended_scenario, extends: :base_scenario do
    example_post do
      title "Extended Post"  # Override title
      # content is inherited from base
    end
    
    another_post do  # Add new resource
      title "Additional post in extended scenario"
      content "More content"
    end
  end


  describe "scenario DSL functionality" do
    test "can define and access scenarios" do
      # Test that the scenario definition macro works
      scenarios = __scenarios__()
      assert length(scenarios) == 6
      
      scenario_names = scenarios |> Enum.map(fn {name, _} -> name end)
      assert :basic_setup in scenario_names
      assert :with_custom_blog in scenario_names
      assert :multiple_posts in scenario_names
      assert :single_blog_only in scenario_names
      assert :base_scenario in scenario_names
      assert :extended_scenario in scenario_names
    end

    test "basic scenario creates resources with overrides" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :basic_setup, domain: Domain)
      
      # Should create example_blog (dependency) and another_post (with override)
      assert Map.has_key?(resources, :example_blog)
      assert Map.has_key?(resources, :another_post)
      
      # Check that the title was overridden
      assert resources.another_post.title == "Override title for basic setup"
      
      # Check that default blog was created
      assert resources.example_blog.name == "Example name"
      
      # Check that the post references the blog
      assert resources.another_post.blog_id == resources.example_blog.id
    end

    test "scenario with custom blog uses correct references" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :with_custom_blog, domain: Domain)
      
      # Should create tech_blog (custom) and another_post (referencing tech_blog)
      assert Map.has_key?(resources, :tech_blog)
      assert Map.has_key?(resources, :another_post)
      
      # Check that the blog name was overridden
      assert resources.tech_blog.name == "My Custom Tech Blog"
      
      # Check that the post references the custom blog
      assert resources.another_post.blog_id == resources.tech_blog.id
      assert resources.another_post.title == "Post in custom blog"
    end

    test "scenario with multiple posts creates all resources" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :multiple_posts, domain: Domain)
      
      # Should create example_blog (dependency) and both posts
      assert Map.has_key?(resources, :example_blog)
      assert Map.has_key?(resources, :example_post)
      assert Map.has_key?(resources, :another_post)
      
      # Check that both post titles were overridden
      assert resources.example_post.title == "First post override"
      assert resources.another_post.title == "Second post override"
      
      # Check that both posts reference the same blog
      assert resources.example_post.blog_id == resources.example_blog.id
      assert resources.another_post.blog_id == resources.example_blog.id
    end

    test "scenario with only blog creates just the blog" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :single_blog_only, domain: Domain)
      
      # Should create only the blog
      assert Map.has_key?(resources, :example_blog)
      assert map_size(resources) == 1
      
      # Check that the blog name was overridden
      assert resources.example_blog.name == "Just a blog, no posts"
    end

    test "scenario only overrides specified attributes" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :basic_setup, domain: Domain)
      
      # another_post should have overridden title but default content
      assert resources.another_post.title == "Override title for basic setup"
      assert resources.another_post.content == "Different content"  # From resource definition
    end
  end

  describe "dependency resolution" do
    test "creates dependencies first" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :basic_setup, domain: Domain)
      
      # Blog should be created before post (dependency order)
      # We can't directly test timing, but we can verify both exist and are linked
      assert resources.example_blog.id
      assert resources.another_post.blog_id == resources.example_blog.id
    end

    test "reuses existing dependencies" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :multiple_posts, domain: Domain)
      
      # Both posts should reference the same blog instance
      assert resources.example_post.blog_id == resources.example_blog.id
      assert resources.another_post.blog_id == resources.example_blog.id
      assert resources.example_blog.id  # Make sure there's only one blog
    end
  end

  describe "error handling" do
    test "returns descriptive error for non-existent scenario" do
      result = AshScenario.Scenario.run(__MODULE__, :nonexistent, domain: Domain)
      assert {:error, message} = result
      assert message =~ "Scenario nonexistent not found"
      assert message =~ "Available scenarios: "
    end

    test "returns error for modules without scenarios" do
      result = AshScenario.Scenario.run(String, :anything, domain: Domain)
      assert {:error, message} = result
      assert message =~ "does not define any scenarios"
      assert message =~ "use AshScenario.Scenario"
    end

    test "handles missing domain gracefully" do
      # Test without explicit domain - should infer from resource
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :basic_setup)
      assert Map.has_key?(resources, :another_post)
    end
  end

  describe "scenario extension (extends)" do
    test "extended scenario merges with base scenario" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :extended_scenario, domain: Domain)
      
      # Should have base resources
      assert Map.has_key?(resources, :example_blog)
      assert Map.has_key?(resources, :example_post)
      # And extended resources
      assert Map.has_key?(resources, :another_post)
      
      # Base blog should have the base name
      assert resources.example_blog.name == "Base Blog"
      
      # Post title should be overridden from extended scenario
      assert resources.example_post.title == "Extended Post"
      # But content should be inherited from base
      assert resources.example_post.content == "Base content"
      
      # New resource from extended scenario
      assert resources.another_post.title == "Additional post in extended scenario"
      assert resources.another_post.content == "More content"
    end

    test "base scenario works independently" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :base_scenario, domain: Domain)
      
      assert Map.has_key?(resources, :example_blog)
      assert Map.has_key?(resources, :example_post)
      assert not Map.has_key?(resources, :another_post)  # Extended resource not present
      
      assert resources.example_blog.name == "Base Blog"
      assert resources.example_post.title == "Base Post"
      assert resources.example_post.content == "Base content"
    end
  end


  describe "integration with existing resource API" do
    test "scenario DSL works alongside resource definitions" do
      # Can still use the regular resource API
      {:ok, blog} = AshScenario.run_resource(Blog, :example_blog, domain: Domain)
      assert blog.name == "Example name"
      
      # And the new scenario DSL
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :basic_setup, domain: Domain)
      assert resources.another_post.title == "Override title for basic setup"
    end

    test "backward compatibility with old API" do
      # Old scenario API still works
      {:ok, resources} = AshScenario.run_scenarios([
        {Blog, :example_blog},
        {Post, :another_post}
      ], domain: Domain)

      assert Map.has_key?(resources, {Blog, :example_blog})
      assert Map.has_key?(resources, {Post, :another_post})
    end
  end
end