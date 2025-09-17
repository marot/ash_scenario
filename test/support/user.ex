defmodule User do
  @moduledoc false
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl],
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id

    attribute :email, :string do
      public? true
      allow_nil? false
    end

    attribute :role, :string do
      public? true
      default "user"
    end

    attribute :name, :string do
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:email, :role, :name]
    end

    update :update do
      accept [:email, :role, :name]
    end
  end

  policies do
    # Anyone can create users (for testing purposes)
    policy action(:create) do
      authorize_if always()
    end

    # Anyone can read users
    policy action(:read) do
      authorize_if always()
    end

    # Only admins can update users
    policy action(:update) do
      authorize_if expr(^actor(:role) == "admin")
    end

    # Only admins can destroy users
    policy action(:destroy) do
      authorize_if expr(^actor(:role) == "admin")
    end
  end

  prototypes do
    prototype :admin_user do
      attr(:email, "admin@example.com")
      attr(:role, "admin")
      attr(:name, "Admin User")
    end

    prototype :regular_user do
      attr(:email, "user@example.com")
      attr(:role, "user")
      attr(:name, "Regular User")
    end

    prototype :moderator_user do
      attr(:email, "moderator@example.com")
      attr(:role, "moderator")
      attr(:name, "Moderator User")
    end
  end
end
