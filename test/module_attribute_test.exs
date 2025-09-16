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

    :ok
  end

  # Scenario using module attributes for values
  scenario :with_module_attributes do
    prototype :example_blog do
      attr(:name, @blog_name)
    end

    prototype :example_post do
      attr(:title, @test_title)
      attr(:content, @test_content)
    end
  end

  # Scenario using module attributes in override
  scenario :override_with_attributes do
    prototype :another_post do
      attr(:title, @test_title)
      attr(:content, @shared_value)
    end
  end

  # Mixed scenario with both literals and module attributes
  scenario :mixed_values do
    prototype :tech_blog do
      attr(:name, "Literal Blog Name")
    end

    prototype :example_post do
      attr(:title, @shared_value)
      attr(:content, "Literal content")
    end
  end

  # Test base scenario with module attribute
  scenario :base_with_attribute do
    prototype :example_blog do
      attr(:name, @blog_name)
    end
  end

  # Extended scenario overriding with module attribute
  scenario :extended_with_attribute do
    extends(:base_with_attribute)

    prototype :example_post do
      attr(:title, @test_title)
    end
  end

  describe "module attribute expansion" do
    test "scenario uses module attribute values correctly" do
      {:ok, resources} =
        AshScenario.run_scenario(__MODULE__, :with_module_attributes, domain: Domain)

      assert resources.example_blog.name == "Blog from Module Attribute"
      assert resources.example_post.title == "Title from Module Attribute"
      assert resources.example_post.content == "Content from Module Attribute"
    end

    test "override with module attributes works" do
      {:ok, resources} =
        AshScenario.run_scenario(__MODULE__, :override_with_attributes, domain: Domain)

      assert resources.another_post.title == "Title from Module Attribute"
      assert resources.another_post.content == "Shared Value"
    end

    test "mixed literals and module attributes work together" do
      {:ok, resources} = AshScenario.run_scenario(__MODULE__, :mixed_values, domain: Domain)

      assert resources.tech_blog.name == "Literal Blog Name"
      assert resources.example_post.title == "Shared Value"
      assert resources.example_post.content == "Literal content"
    end

    test "module attributes work in scenario extension" do
      {:ok, resources} =
        AshScenario.run_scenario(__MODULE__, :extended_with_attribute, domain: Domain)

      # Base scenario's module attribute should be used
      assert resources.example_blog.name == "Blog from Module Attribute"
      # Extended scenario's module attribute should be used
      assert resources.example_post.title == "Title from Module Attribute"
    end
  end
end
