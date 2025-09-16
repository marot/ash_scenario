defmodule AshScenario.Examples.Project do
  @moduledoc """
  Launch project owned by an organization.
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

    attribute :launch_date, :date do
      allow_nil?(true)
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
      accept([:name, :launch_date, :organization_id])
    end

    update :reschedule do
      accept([:launch_date])
    end
  end

  prototypes do
    prototype :launch_hub do
      attr(:name, "Launch Readiness")
      attr(:launch_date, ~D[2024-05-01])
      attr(:organization_id, :acme_corp)
    end

    prototype :expansion_path do
      attr(:name, "Expansion Planning")
      attr(:launch_date, ~D[2024-06-01])
      attr(:organization_id, :globex)
    end
  end
end
