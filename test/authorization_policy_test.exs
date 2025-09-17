defmodule AuthorizationPolicyTest do
  use ExUnit.Case

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "authorization policies" do
    test "admin can create restricted posts" do
      result = AshScenario.run([{AuthorizedPost, :admin_post}], domain: Domain)

      assert {:ok, resources} = result
      post = resources[{AuthorizedPost, :admin_post}]
      assert post.title == "Admin Only Post"
      assert post.restricted == true
    end

    test "regular user can create non-restricted posts" do
      result = AshScenario.run([{AuthorizedPost, :user_post}], domain: Domain)

      assert {:ok, resources} = result
      post = resources[{AuthorizedPost, :user_post}]
      assert post.title == "User Post"
      assert post.restricted == false
    end

    test "creation fails without actor when authorization is enabled" do
      # Force authorize? without providing an actor
      result =
        AshScenario.run(
          [{AuthorizedPost, :unauthorized_post}],
          domain: Domain,
          overrides: %{
            {AuthorizedPost, :unauthorized_post} => %{authorize?: true}
          }
        )

      assert {:error, _reason} = result
    end

    test "actor dependency is resolved before dependent resources" do
      # The admin_post prototype references :admin_user as both author and actor
      result = AshScenario.run([{AuthorizedPost, :admin_post}], domain: Domain)

      assert {:ok, resources} = result

      # Both user and post should be created
      admin_user = resources[{User, :admin_user}]
      admin_post = resources[{AuthorizedPost, :admin_post}]

      assert admin_user != nil
      assert admin_post != nil
      assert admin_post.author_id == admin_user.id
    end

    test "multiple posts with different actors are created correctly" do
      result =
        AshScenario.run(
          [
            {AuthorizedPost, :admin_post},
            {AuthorizedPost, :user_post}
          ],
          domain: Domain
        )

      assert {:ok, resources} = result

      admin_post = resources[{AuthorizedPost, :admin_post}]
      user_post = resources[{AuthorizedPost, :user_post}]
      admin_user = resources[{User, :admin_user}]
      regular_user = resources[{User, :regular_user}]

      assert admin_post.author_id == admin_user.id
      assert user_post.author_id == regular_user.id
    end

    test "authorize? defaults to true when actor is present" do
      # The user_post has an actor but no explicit authorize? field
      # It should default to true and still work
      result = AshScenario.run([{AuthorizedPost, :user_post}], domain: Domain)

      assert {:ok, _resources} = result
    end

    test "authorize? can be explicitly set to false to bypass authorization" do
      # Create a post without an actor but with authorize? false
      result =
        AshScenario.run(
          [{AuthorizedPost, :unauthorized_post}],
          domain: Domain,
          overrides: %{
            {AuthorizedPost, :unauthorized_post} => %{authorize?: false}
          }
        )

      # Should succeed even without an actor because authorization is disabled
      assert {:ok, resources} = result
      post = resources[{AuthorizedPost, :unauthorized_post}]
      assert post.title == "Post Without Actor"
    end
  end

  describe "runtime actor overrides" do
    test "actor can be overridden at runtime with a prototype reference" do
      # Override the actor at runtime
      result =
        AshScenario.run(
          [{AuthorizedPost, :admin_post}],
          domain: Domain,
          overrides: %{
            {AuthorizedPost, :admin_post} => %{
              actor: :moderator_user,
              title: "Modified by Moderator"
            }
          }
        )

      assert {:ok, resources} = result
      post = resources[{AuthorizedPost, :admin_post}]
      moderator = resources[{User, :moderator_user}]

      assert post.title == "Modified by Moderator"
      assert moderator != nil
    end

    test "actor can be overridden with module-scoped reference" do
      result =
        AshScenario.run(
          [{AuthorizedPost, :admin_post}],
          domain: Domain,
          overrides: %{
            {AuthorizedPost, :admin_post} => %{
              actor: {User, :regular_user},
              title: "Modified by Regular User"
            }
          }
        )

      assert {:ok, resources} = result
      post = resources[{AuthorizedPost, :admin_post}]
      user = resources[{User, :regular_user}]

      assert post.title == "Modified by Regular User"
      assert user != nil
    end

    test "runtime actor override creates proper dependencies" do
      # When we override the actor, the new actor should be created as a dependency
      result =
        AshScenario.run(
          [{AuthorizedPost, :admin_post}],
          domain: Domain,
          overrides: %{
            {AuthorizedPost, :admin_post} => %{
              actor: :moderator_user
            }
          }
        )

      assert {:ok, resources} = result

      # The moderator should be created even though it wasn't originally referenced
      moderator = resources[{User, :moderator_user}]
      assert moderator != nil
      assert moderator.role == "moderator"
    end
  end
end
