defmodule AshScenario.TelemetryHandlerTest do
  use ExUnit.Case, async: true

  alias AshScenario.TelemetryHandler

  test "tracks blog creation with ID" do
    test_setup = TelemetryHandler.setup_for_test("blog_creation")
    
    # Initially no resources changed
    assert TelemetryHandler.get_changed_resources(test_setup.agent_name) == []
    
    # Create a blog
    {:ok, blog} = Blog
    |> Ash.Changeset.for_create(:create, %{name: "Test Blog"})
    |> Ash.create()
    
    # Should track the blog resource with its ID
    changed_resources = TelemetryHandler.get_changed_resources(test_setup.agent_name)
    
    assert length(changed_resources) == 1
    
    [resource_info] = changed_resources
    assert resource_info.resource == Blog
    assert resource_info.primary_keys.id == blog.id
    
    # Cleanup
    TelemetryHandler.teardown_test(test_setup)
  end

end