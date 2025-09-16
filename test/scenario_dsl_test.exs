defmodule AshScenario.ScenarioDslTest do
  use ExUnit.Case
  use AshScenario.Scenario

  setup do
    # Ensure registry is started and clear for each test
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  # Define test scenarios using the new DSL
  scenario :basic_setup do
    # TODO: Ask if this is supported somehow
    # another_post do
    #   title("Override title for basic setup")
    # end

    prototype :another_post do
      attr(:title, "Override title for basic setup")
    end
  end

  scenario :with_custom_blog do
    # tech_blog do
    #   name "My Custom Tech Blog"
    # end

    # another_post do
    #   title("Post in custom blog")
    #   blog_id(:tech_blog)
    # end
    prototype :tech_blog do
      attr(:name, "My Custom Tech Blog")
    end

    prototype :another_post do
      attr(:title, "Post in custom blog")
      attr(:blog_id, :tech_blog)
    end
  end

  scenario :single_blog_only do
    prototype :example_blog do
      attr(:name, "Just a blog, no posts")
    end
  end

  # Test scenarios for new features
  scenario :base_scenario do
    prototype :example_blog do
      attr(:name, "Base Blog")
    end

    prototype :example_post do
      attr(:title, "Base Post")
      attr(:content, "Base content")
    end
  end

  scenario :extended_scenario do
    extends(:base_scenario)

    prototype :example_post do
      # Override title
      attr(:title, "Extended Post")
      # content is inherited from base
    end

    # Add new resource
    prototype :another_post do
      attr(:title, "Additional post in extended scenario")
      attr(:content, "More content")
    end
  end

  scenario :diamond_setup do
    prototype :featured_post do
      attr(:title, "Scenario Featured")
    end
  end

  describe "scenario DSL functionality" do
    test "can define and access scenarios" do
      # Test that the scenario definition macro works
      scenarios = AshScenario.ScenarioInfo.scenarios(__MODULE__)
      assert length(scenarios) == 7

      scenario_names = scenarios |> Enum.map(fn %{name: name} -> name end)
      assert :basic_setup in scenario_names
      assert :with_custom_blog in scenario_names
      assert :multiple_posts in scenario_names
      assert :single_blog_only in scenario_names
      assert :base_scenario in scenario_names
      assert :extended_scenario in scenario_names
      assert :diamond_setup in scenario_names
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

    scenario :multiple_posts do
      prototype :example_post do
        attr(:title, "First post override")
      end

      prototype :another_post do
        attr(:title, "Second post override")
      end
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
      # From prototype definition
      assert resources.another_post.content == "Different content"
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
      # Make sure there's only one blog
      assert resources.example_blog.id
    end

    test "resolves diamond dependencies" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :diamond_setup, domain: Domain)

      assert Map.has_key?(resources, :example_blog)
      assert Map.has_key?(resources, :tech_category)
      assert Map.has_key?(resources, :lifestyle_category)
      assert Map.has_key?(resources, :featured_post)

      assert resources.tech_category.blog_id == resources.example_blog.id
      assert resources.lifestyle_category.blog_id == resources.example_blog.id
      assert resources.featured_post.blog_id == resources.example_blog.id
      assert resources.featured_post.primary_category_id == resources.tech_category.id
      assert resources.featured_post.secondary_category_id == resources.lifestyle_category.id
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
      # Extended resource not present
      assert not Map.has_key?(resources, :another_post)

      assert resources.example_blog.name == "Base Blog"
      assert resources.example_post.title == "Base Post"
      assert resources.example_post.content == "Base content"
    end
  end

  describe "integration with existing prototype API" do
    test "scenario DSL works alongside prototype definitions" do
      # Can still use the regular prototype API
      {:ok, blog} = AshScenario.run_prototype(Blog, :example_blog, domain: Domain)
      assert blog.name == "Example name"

      # And the new scenario DSL
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :basic_setup, domain: Domain)
      assert resources.another_post.title == "Override title for basic setup"
    end

    test "backward compatibility with old API" do
      # Old scenario API still works
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {Blog, :example_blog},
            {Post, :another_post}
          ],
          domain: Domain
        )

      assert Map.has_key?(resources, {Blog, :example_blog})
      assert Map.has_key?(resources, {Post, :another_post})
    end
  end
end
