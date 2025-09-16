defmodule AshScenario.Examples.Task do
  @moduledoc """
  Launch task assigned to a project member.
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

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :status, :string do
      allow_nil?(false)
      default("backlog")
      public?(true)
    end

    attribute :due_on, :date do
      allow_nil?(true)
      public?(true)
    end

    attribute :project_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :assignee_id, :uuid do
      allow_nil?(true)
      public?(true)
    end
  end

  relationships do
    belongs_to :project, AshScenario.Examples.Project do
      public?(true)
      attribute_writable?(true)
    end

    belongs_to :assignee, AshScenario.Examples.Member do
      public?(true)
      attribute_writable?(true)
    end

    belongs_to :organization, AshScenario.Examples.Organization do
    end
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:title, :status, :due_on, :project_id, :assignee_id, :organization_id])
    end

    update :update_details do
      accept([:status, :due_on, :assignee_id])
    end
  end

  prototypes do
    prototype :draft_release_notes do
      attr(:title, "Draft release notes")
      attr(:status, "draft")
      attr(:due_on, ~D[2024-04-10])
      attr(:project_id, :launch_hub)
      attr(:assignee_id, :product_manager)
      attr(:organization_id, :acme_corp)
    end

    prototype :schedule_webinar do
      attr(:title, "Schedule customer webinar")
      attr(:status, "awaiting_input")
      attr(:due_on, ~D[2024-04-14])
      attr(:project_id, :launch_hub)
      attr(:assignee_id, :lead_engineer)
      attr(:organization_id, :acme_corp)
    end
  end
end
