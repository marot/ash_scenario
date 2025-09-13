defmodule AshScenario.SimpleCompileTimeTest do
  use ExUnit.Case

  # Module that will be compiled BEFORE the test module
  defmodule Helpers do
    def get_value, do: "from_helper_function"
    def get_number, do: 42
  end

  # Now we can use the module
  use AshScenario.Scenario

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    AshScenario.clear_prototypes()
    AshScenario.register_prototypes(Post)
    AshScenario.register_prototypes(Blog)
    :ok
  end

  # Test with module attributes - these work perfectly
  @my_title "Title from attribute"
  @my_content "Content from attribute"

  scenario :attributes_only do
    prototype :example_blog do
      attr(:name, "Static blog name")
    end

    prototype :example_post do
      attr(:title, @my_title)
      attr(:content, @my_content)
    end
  end

  # Test with simple zero-arity remote function calls
  scenario :simple_functions do
    prototype :tech_blog do
      attr(:name, Helpers.get_value())
    end

    prototype :another_post do
      attr(:title, Helpers.get_value())
      # Built-in function
      attr(:content, System.version())
    end
  end

  # Test with date sigil
  scenario :date_sigil do
    prototype :example_blog do
      attr(:name, "Blog with dates")
    end

    prototype :example_post do
      attr(:title, "Post with publication date")
      attr(:publication_date, ~D[2016-04-12])
    end
  end

  describe "module attributes" do
    test "module attributes work correctly" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :attributes_only, domain: Domain)

      assert resources.example_post.title == "Title from attribute"
      assert resources.example_post.content == "Content from attribute"
    end
  end

  describe "function calls" do
    test "simple remote function calls are evaluated" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :simple_functions, domain: Domain)

      assert resources.tech_blog.name == "from_helper_function"
      assert resources.another_post.title == "from_helper_function"
      assert resources.another_post.content == System.version()
    end
  end

  describe "date sigils" do
    test "date sigils work correctly at runtime" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :date_sigil, domain: Domain)

      assert resources.example_post.publication_date == ~D[2016-04-12]
      assert %Date{year: 2016, month: 4, day: 12} = resources.example_post.publication_date
    end
  end
end
