defmodule AuthorizedPost do
  @moduledoc false
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl],
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
      allow_nil? false
    end

    attribute :content, :string do
      public? true
    end

    attribute :status, :string do
      public? true
      default "draft"
    end

    attribute :restricted, :boolean do
      public? true
      default false
    end
  end

  relationships do
    belongs_to :author, User do
      public? true
      allow_nil? false
    end

    belongs_to :blog, Blog do
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title, :content, :status, :restricted, :author_id, :blog_id]
    end

    update :update do
      accept [:title, :content, :status, :restricted]
    end

    destroy :destroy
  end

  policies do
    # Only authenticated users can create posts
    policy action(:create) do
      authorize_if actor_present()
    end

    # Anyone can read non-restricted posts
    policy action(:read) do
      authorize_if expr(restricted == false)
      authorize_if expr(^actor(:role) == "admin")
      authorize_if expr(author_id == ^actor(:id))
    end

    # Only authors can update their own posts, admins can update any
    policy action(:update) do
      authorize_if expr(^actor(:role) == "admin")
      authorize_if expr(author_id == ^actor(:id))
    end

    # Only authors can destroy their own posts, admins can destroy any
    policy action(:destroy) do
      authorize_if expr(^actor(:role) == "admin")
      authorize_if expr(author_id == ^actor(:id))
    end
  end

  prototypes do
    prototype :admin_post do
      actor :admin_user
      attr(:title, "Admin Only Post")
      attr(:content, "This post was created by an admin")
      attr(:restricted, true)
      attr(:author_id, :admin_user)
    end

    prototype :user_post do
      actor :regular_user
      attr(:title, "User Post")
      attr(:content, "This post was created by a regular user")
      attr(:restricted, false)
      attr(:author_id, :regular_user)
    end

    prototype :restricted_post do
      actor :admin_user
      attr(:title, "Restricted Post")
      attr(:content, "This is a restricted post")
      attr(:restricted, true)
      attr(:author_id, :admin_user)
    end

    prototype :unauthorized_post do
      attr(:title, "Post Without Actor")
      attr(:content, "This post should fail to create with authorization")
      attr(:author_id, :regular_user)
      # No actor specified - should fail if authorize? is true
    end
  end
end
