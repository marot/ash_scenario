defmodule AshScenario.Examples.Organization do
  @moduledoc """
  Tenant resource representing a company that is preparing a product launch.
  """

  use Ash.Resource,
    domain: AshScenario.Examples.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshScenario.Dsl]

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
    end
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :slug])
    end
  end

  prototypes do
    prototype :acme_corp do
      attr(:name, "Acme Launch Collective")
      attr(:slug, "acme")
    end

    prototype :globex do
      attr(:name, "Globex Innovation Lab")
      attr(:slug, "globex")
    end
  end
end
