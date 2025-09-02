defmodule DependencyResolutionTest do
  use ExUnit.Case

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    AshScenario.clear_prototypes()
    
    # Register our test resources
    AshScenario.register_prototypes(Blog)
    AshScenario.register_prototypes(Post)
    
    :ok
  end

  describe "automatic dependency resolution" do
    test "run_resources automatically pulls in referenced dependencies" do
      # This should work: Only specify the post, blog should be created automatically
      {:ok, resources} = AshScenario.run_prototypes([
        {Post, :example_post}  # References :example_blog in blog_id
      ], domain: Domain)

      # Both records should be created
      blog = resources[{Blog, :example_blog}]
      post = resources[{Post, :example_post}]

      assert blog != nil, "Referenced blog should be created automatically"
      assert post != nil, "Requested post should be created"
      assert blog.name == "Example name"
      assert post.title == "A post title"
      assert post.blog_id == blog.id, "Reference should be resolved to actual ID"
    end

    test "run_prototype automatically pulls in referenced dependencies" do
      # Single resource should also pull in dependencies
      {:ok, post} = AshScenario.run_prototype(Post, :example_post, domain: Domain)

      assert post.title == "A post title"
      assert is_binary(post.blog_id), "blog_id should be resolved to UUID string"
    end

    test "consistency between Scenario.run and run_resources" do
      # Set up a test scenario
      defmodule TestScenarioModule do
        use AshScenario.Scenario

        scenario :test_post do
          example_post do
            title "Scenario Post Title"
          end
        end
      end

      # Both APIs should produce the same dependency resolution behavior
      {:ok, scenario_resources} = AshScenario.Scenario.run(TestScenarioModule, :test_post, domain: Domain)
      
      AshScenario.clear_prototypes()
      AshScenario.register_prototypes(Blog)
      AshScenario.register_prototypes(Post)
      
      {:ok, direct_resources} = AshScenario.run_prototypes([
        {Post, :example_post}
      ], domain: Domain)

      # Both should have created the blog dependency
      scenario_blog = scenario_resources.example_blog
      direct_blog = direct_resources[{Blog, :example_blog}]
      
      assert scenario_blog != nil
      assert direct_blog != nil
      assert scenario_blog.name == direct_blog.name
    end

    test "multi-level dependencies are resolved" do
      # Create a comment resource that depends on post, which depends on blog
      defmodule Comment do
        use Ash.Resource,
          domain: Domain,
          extensions: [AshScenario.Dsl]

        attributes do
          uuid_primary_key :id
          attribute :content, :string, public?: true
        end

        relationships do
          belongs_to :post, Post, public?: true
        end

        actions do
          defaults [:read]
          create :create do
            accept [:content, :post_id]
          end
        end

        prototypes do
          prototype :example_comment do
            attr :content, "Great post!"
            attr :post_id, :example_post
          end
        end
      end

      # Register the new resource
      AshScenario.register_prototypes(Comment)

      # Only request the comment - should pull in post and blog
      {:ok, resources} = AshScenario.run_prototypes([
        {Comment, :example_comment}
      ], domain: Domain)

      comment = resources[{Comment, :example_comment}]
      post = resources[{Post, :example_post}]
      blog = resources[{Blog, :example_blog}]

      assert comment != nil, "Comment should be created"
      assert post != nil, "Post dependency should be created automatically"
      assert blog != nil, "Blog dependency should be created automatically"
      
      assert comment.content == "Great post!"
      assert comment.post_id == post.id
      assert post.blog_id == blog.id
    end

    test "explicit and implicit prototypes are both created" do
      # Mix explicit and implicit dependencies
      {:ok, resources} = AshScenario.run_prototypes([
        {Blog, :tech_blog},    # Explicitly requested
        {Post, :example_post}  # Implicitly pulls in :example_blog
      ], domain: Domain)

      tech_blog = resources[{Blog, :tech_blog}]
      example_blog = resources[{Blog, :example_blog}]
      post = resources[{Post, :example_post}]

      assert tech_blog != nil, "Explicitly requested blog should be created"
      assert example_blog != nil, "Dependency blog should be created"
      assert post != nil, "Post should be created"
      
      assert tech_blog.name == "Tech Blog"
      assert example_blog.name == "Example name"
      assert post.blog_id == example_blog.id, "Post should reference the dependency blog"
    end
  end
end
