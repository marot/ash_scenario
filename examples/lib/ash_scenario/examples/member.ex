defmodule AshScenario.Examples.Member do
  @moduledoc """
  Organization member participating in a launch project.
  """

  use Ash.Resource,
    domain: AshScenario.Examples.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshScenario.Dsl]

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :role, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :email, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :organization_id, :uuid do
      allow_nil?(false)
      public?(true)
    end
  end

  relationships do
    belongs_to :organization, AshScenario.Examples.Organization do
    end
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :role, :email, :organization_id])
    end
  end

  prototypes do
    create do
      function {__MODULE__, :test, []}
    end

    prototype :product_manager do
      attr(:name, "Jordan Rivers")
      attr(:role, "Product Manager")
      attr(:email, "jordan@acme.test")
      attr(:organization_id, :acme_corp)
    end

    prototype :lead_engineer do
      attr(:name, "Sasha Patel")
      attr(:role, "Lead Engineer")
      attr(:email, "sasha@acme.test")
      attr(:organization_id, :acme_corp)
    end
  end

  def test(attrs, ctx) do
    dbg(attrs)
    dbg(ctx)

    Ash.create(__MODULE__, attrs, ctx)
  end
end
