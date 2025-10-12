defmodule AuthorizationScenarioTest do
  use ExUnit.Case
  use AshScenario.Scenario

  setup do
    case AshScenario.start_registry() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  scenario :with_regular_user_override do
    prototype {AuthorizedPost, :admin_post} do
      actor {User, :regular_user}
      attr(:title, "Post by Regular User")
    end
  end

  scenario :with_admin_actor do
    prototype {AuthorizedPost, :user_post} do
      actor {User, :admin_user}
      attr(:title, "User Post with Admin Actor")
    end
  end

  scenario :without_actor_override do
    prototype {AuthorizedPost, :admin_post} do
      attr(:title, "Prototype Actor Used")
    end
  end

  describe "scenario actor overrides" do
    test "scenario actor overrides prototype actor" do
      # admin_post prototype has actor :admin_user and author_id :admin_user
      # scenario overrides actor with :regular_user but NOT author_id
      {:ok, resources} =
        AshScenario.run_scenario(__MODULE__, :with_regular_user_override, domain: Domain)

      # Both users should be created
      assert resources.admin_user != nil
      assert resources.regular_user != nil

      # Post should be created with regular_user as actor
      post = resources.admin_post
      assert post.title == "Post by Regular User"

      # The author is STILL admin_user (from prototype's author_id attribute)
      # Only the ACTOR was overridden, not the author_id
      admin_user = resources.admin_user
      assert post.author_id == admin_user.id
    end

    test "scenario can override actor on different prototype" do
      # user_post prototype has actor :regular_user
      # scenario overrides it with :admin_user
      {:ok, resources} = AshScenario.run_scenario(__MODULE__, :with_admin_actor, domain: Domain)

      # Both users should be created
      assert resources.admin_user != nil
      assert resources.regular_user != nil

      # Post should be created with admin_user as actor
      post = resources.user_post
      assert post.title == "User Post with Admin Actor"

      # The author should be the regular_user (from prototype)
      regular_user = resources.regular_user
      assert post.author_id == regular_user.id
    end

    test "scenario without actor override uses prototype actor" do
      # admin_post prototype has actor :admin_user
      # scenario doesn't override actor, so it should use prototype's actor
      {:ok, resources} =
        AshScenario.run_scenario(__MODULE__, :without_actor_override, domain: Domain)

      # Admin user should be created (from prototype)
      assert resources.admin_user != nil

      # Post should be created with admin_user as actor (from prototype)
      post = resources.admin_post
      assert post.title == "Prototype Actor Used"

      # The author should be the admin_user
      admin_user = resources.admin_user
      assert post.author_id == admin_user.id
    end
  end
end
