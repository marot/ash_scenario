# Test scenario module needs to be defined before test module
defmodule AshScenario.StructBuilderTest.TestScenarioModule do
  use AshScenario.Scenario

  scenario :test_setup do
    prototype {AshScenario.StructBuilderTest.Blog, :example_blog} do
      attr(:name, "Test Blog")
    end

    prototype {AshScenario.StructBuilderTest.Post, :example_post} do
      attr(:title, "Test Post")
      attr(:content, "Test Content")
    end
  end
end

defmodule AshScenario.StructBuilderTest do
  alias AshScenario.StructBuilderTest.TestScenarioModule
  use ExUnit.Case

  defmodule TestDomain do
    use Ash.Domain

    resources do
      resource AshScenario.StructBuilderTest.Blog
      resource AshScenario.StructBuilderTest.Post
    end
  end

  defmodule Blog do
    use Ash.Resource,
      domain: AshScenario.StructBuilderTest.TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshScenario.Dsl]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false
      timestamps()
    end

    actions do
      defaults [:create, :read, :update, :destroy]
    end

    prototypes do
      prototype :example_blog do
        attr(:name, "Example Blog")
      end
    end
  end

  defmodule Post do
    use Ash.Resource,
      domain: AshScenario.StructBuilderTest.TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshScenario.Dsl]

    attributes do
      uuid_primary_key :id
      attribute :title, :string, allow_nil?: false
      attribute :content, :string
      attribute :blog_id, :uuid
      timestamps()
    end

    relationships do
      belongs_to :blog, Blog, attribute_writable?: true
    end

    actions do
      defaults [:create, :read, :update, :destroy]
    end

    prototypes do
      prototype :example_post do
        attr(:title, "Example Post")
        attr(:content, "This is example content")
        attr(:blog_id, :example_blog)
      end
    end
  end

  setup do
    :ok
  end

  describe "run with struct strategy" do
    test "creates a single struct without database persistence" do
      {:ok, resources} = AshScenario.run([{Blog, :example_blog}], strategy: :struct)
      blog = resources[{Blog, :example_blog}]

      assert blog.__struct__ == Blog
      assert blog.name == "Example Blog"
      assert blog.id != nil
      assert blog.inserted_at != nil
      assert blog.updated_at != nil
    end

    test "creates a struct with overrides" do
      {:ok, resources} =
        AshScenario.run([{Blog, :example_blog}],
          strategy: :struct,
          overrides: %{name: "Custom Blog"}
        )

      blog = resources[{Blog, :example_blog}]

      assert blog.name == "Custom Blog"
    end
  end

  describe "run with struct strategy for multiple resources" do
    test "creates multiple structs with dependency resolution" do
      {:ok, structs} =
        AshScenario.run(
          [
            {Blog, :example_blog},
            {Post, :example_post}
          ],
          strategy: :struct
        )

      blog = structs[{Blog, :example_blog}]
      post = structs[{Post, :example_post}]

      assert blog.__struct__ == Blog
      assert post.__struct__ == Post
      assert post.title == "Example Post"

      # The blog_id should be resolved to the actual blog struct
      assert post.blog_id == blog
    end
  end

  describe "run_scenario with struct strategy" do
    test "creates structs from a scenario without persistence" do
      _scenarios = AshScenario.ScenarioInfo.scenarios(TestScenarioModule)

      {:ok, structs} =
        AshScenario.run_scenario(__MODULE__.TestScenarioModule, :test_setup, strategy: :struct)

      blog = structs.example_blog
      post = structs.example_post

      assert blog.__struct__ == Blog
      assert blog.name == "Test Blog"

      assert post.__struct__ == Post
      assert post.title == "Test Post"
      assert post.content == "Test Content"

      # The blog reference should be resolved to the struct
      assert post.blog_id == blog
    end
  end
end
