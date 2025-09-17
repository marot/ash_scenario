defmodule AuthorizationTest do
  use ExUnit.Case

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "actor field in prototype DSL" do
    test "prototype accepts actor field as a reference to another prototype" do
      # This test verifies that the DSL accepts the actor field
      # It should fail initially since we haven't implemented the feature yet
      prototypes = AshScenario.prototypes(AuthorizedPost)
      admin_post = Enum.find(prototypes, &(&1.ref == :admin_post))

      # The actor field should be present in the prototype attributes
      assert admin_post.attributes[:actor] == :admin_user
    end

    test "prototype accepts authorize? field" do
      prototypes = AshScenario.prototypes(AuthorizedPost)
      restricted_post = Enum.find(prototypes, &(&1.ref == :restricted_post))

      # The authorize? field should be present
      assert restricted_post.attributes[:authorize?] == true
    end

    test "actor prototype is resolved as a dependency" do
      # When we run a prototype with an actor reference,
      # the actor should be created first as a dependency
      result = AshScenario.run([{AuthorizedPost, :admin_post}], domain: Domain)

      assert {:ok, resources} = result
      # Both the user (actor) and post should be created
      assert resources[{User, :admin_user}] != nil
      assert resources[{AuthorizedPost, :admin_post}] != nil

      # The post's author should be the created user
      post = resources[{AuthorizedPost, :admin_post}]
      user = resources[{User, :admin_user}]
      assert post.author_id == user.id
    end

    test "resource is created with actor when actor field is specified" do
      # This test verifies that the actor is actually used during creation
      # We'll check this by ensuring a post that requires authorization succeeds
      result = AshScenario.run([{AuthorizedPost, :user_post}], domain: Domain)

      assert {:ok, resources} = result
      post = resources[{AuthorizedPost, :user_post}]
      assert post.title == "User Post"
    end

    test "creation fails when no actor is provided but authorize? is true" do
      # This test should verify that authorization actually happens
      # We'll need to explicitly set authorize? to true for a prototype without an actor
      result =
        AshScenario.run(
          [{AuthorizedPost, :unauthorized_post}],
          domain: Domain,
          # Force authorization without an actor
          overrides: %{{AuthorizedPost, :unauthorized_post} => %{authorize?: true}}
        )

      # This should fail because no actor is present and policies require one
      assert {:error, _reason} = result
    end
  end
end
