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
    example_blog do
      name "Static blog name"
    end

    example_post do
      title @my_title
      content @my_content
    end
  end

  # Test with simple zero-arity remote function calls
  scenario :simple_functions do
    tech_blog do
      name Helpers.get_value()
    end

    another_post do
      title Helpers.get_value()
      content System.version()  # Built-in function
    end
  end

  # Test with date sigil
  scenario :date_sigil do
    example_blog do
      name "Blog with dates"
    end

    example_post do
      title "Post with publication date"
      publication_date ~D[2016-04-12]
    end
  end

  describe "module attributes" do
    test "module attributes work correctly" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :attributes_only, domain: Domain)

      assert resources.example_post.title == "Title from attribute"
      assert resources.example_post.content == "Content from attribute"
    end

    test "attributes are expanded at compile time" do
      scenarios = __scenarios__()
      {_name, overrides} = Enum.find(scenarios, fn {name, _} -> name == :attributes_only end)
      
      assert overrides[:example_post][:title] == "Title from attribute"
      assert overrides[:example_post][:content] == "Content from attribute"
    end
  end

  describe "function calls" do
    test "simple remote function calls are evaluated" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :simple_functions, domain: Domain)

      assert resources.tech_blog.name == "from_helper_function"
      assert resources.another_post.title == "from_helper_function"
      assert resources.another_post.content == System.version()
    end

    test "function values are stored in scenarios" do
      scenarios = __scenarios__()
      {_name, overrides} = Enum.find(scenarios, fn {name, _} -> name == :simple_functions end)
      
      # These should be actual values, not AST
      assert overrides[:tech_blog][:name] == "from_helper_function"
      assert overrides[:another_post][:title] == "from_helper_function"
      assert overrides[:another_post][:content] == System.version()
      
      # Verify they're not AST tuples
      refute is_tuple(overrides[:tech_blog][:name])
      refute is_tuple(overrides[:another_post][:title])
    end
  end

  describe "date sigils" do
    test "date sigils are expanded at compile time" do
      scenarios = __scenarios__()
      {_name, overrides} = Enum.find(scenarios, fn {name, _} -> name == :date_sigil end)
      
      # Date should be expanded to an actual Date struct
      assert overrides[:example_post][:publication_date] == ~D[2016-04-12]
      assert %Date{year: 2016, month: 4, day: 12} = overrides[:example_post][:publication_date]
    end

    test "date sigils work correctly at runtime" do
      {:ok, resources} = AshScenario.Scenario.run(__MODULE__, :date_sigil, domain: Domain)

      assert resources.example_post.publication_date == ~D[2016-04-12]
      assert %Date{year: 2016, month: 4, day: 12} = resources.example_post.publication_date
    end
  end
end