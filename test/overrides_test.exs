defmodule AshScenario.OverridesTest do
  use ExUnit.Case

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

  test "run_resource supports inline overrides" do
    {:ok, blog} = AshScenario.run_prototype(Blog, :example_blog,
      domain: Domain,
      overrides: %{name: "Custom name"}
    )

    assert blog.name == "Custom name"
  end

  test "run_resources supports per-tuple overrides" do
    {:ok, resources} = AshScenario.run_prototypes([
      {Blog, :example_blog, %{name: "Tuple Blog"}},
      {Post, :example_post, %{title: "Tuple Post"}}
    ], domain: Domain)

    blog = resources[{Blog, :example_blog}]
    post = resources[{Post, :example_post}]

    assert blog.name == "Tuple Blog"
    assert post.title == "Tuple Post"
    assert post.blog_id == blog.id
  end

  test "run_resources supports top-level overrides map" do
    overrides = %{
      {Blog, :example_blog} => %{name: "Top Blog"},
      {Post, :example_post} => %{title: "Top Post"}
    }

    {:ok, resources} = AshScenario.run_prototypes([
      {Blog, :example_blog},
      {Post, :example_post}
    ], domain: Domain, overrides: overrides)

    blog = resources[{Blog, :example_blog}]
    post = resources[{Post, :example_post}]

    assert blog.name == "Top Blog"
    assert post.title == "Top Post"
    assert post.blog_id == blog.id
  end
end
