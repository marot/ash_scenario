defmodule AshScenario.ModuleAttributeTest do
  use ExUnit.Case
  use AshScenario.Scenario

  # Define module attributes to use in scenarios
  @test_title "Title from Module Attribute"
  @test_content "Content from Module Attribute"
  @blog_name "Blog from Module Attribute"
  @shared_value "Shared Value"

  setup do
    # Ensure registry is started and clear for each test
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    AshScenario.clear_prototypes()
    AshScenario.register_prototypes(Post)
    AshScenario.register_prototypes(Blog)
    :ok
  end

  # Scenario using module attributes for values
  scenario :with_module_attributes do
    example_blog do
      name @blog_name
    end

    example_post do
      title(@test_title)
      content(@test_content)
    end
  end

  # Scenario using module attributes in override
  scenario :override_with_attributes do
    another_post do
      title(@test_title)
      content(@shared_value)
    end
  end

  # Mixed scenario with both literals and module attributes
  scenario :mixed_values do
    tech_blog do
      name "Literal Blog Name"
    end

    example_post do
      title(@shared_value)
      content("Literal content")
    end
  end

  # Test base scenario with module attribute
  scenario :base_with_attribute do
    example_blog do
      name @blog_name
    end
  end

  # Extended scenario overriding with module attribute
  scenario :extended_with_attribute, extends: :base_with_attribute do
    example_post do
      title(@test_title)
    end
  end

  describe "module attribute expansion" do
    test "scenario uses module attribute values correctly" do
      {:ok, resources} =
        AshScenario.Scenario.run(__MODULE__, :with_module_attributes, domain: Domain)

      assert resources.example_blog.name == "Blog from Module Attribute"
      assert resources.example_post.title == "Title from Module Attribute"
      assert resources.example_post.content == "Content from Module Attribute"
    end

    test "override with module attributes works" do
      {:ok, resources} =
        AshScenario.Scenario.run(__MODULE__, :override_with_attributes, domain: Domain)

      assert resources.another_post.title == "Title from Module Attribute"
      assert resources.another_post.content == "Shared Value"
    end

    test "mixed literals and module attributes work together" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :mixed_values, domain: Domain)

      assert resources.tech_blog.name == "Literal Blog Name"
      assert resources.example_post.title == "Shared Value"
      assert resources.example_post.content == "Literal content"
    end

    test "module attributes work in scenario extension" do
      {:ok, resources} =
        AshScenario.Scenario.run(__MODULE__, :extended_with_attribute, domain: Domain)

      # Base scenario's module attribute should be used
      assert resources.example_blog.name == "Blog from Module Attribute"
      # Extended scenario's module attribute should be used
      assert resources.example_post.title == "Title from Module Attribute"
    end

    test "module attributes are evaluated at compile time" do
      # Verify that the scenarios have the expanded values
      scenarios = __scenarios__()

      # Find the :with_module_attributes scenario
      {_name, overrides} =
        Enum.find(scenarios, fn {name, _} -> name == :with_module_attributes end)

      # Check that the module attributes were expanded to their values
      assert overrides[:example_blog][:name] == "Blog from Module Attribute"
      assert overrides[:example_post][:title] == "Title from Module Attribute"
      assert overrides[:example_post][:content] == "Content from Module Attribute"
    end
  end
end
