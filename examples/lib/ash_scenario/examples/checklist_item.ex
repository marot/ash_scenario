defmodule AshScenario.Examples.ChecklistItem do
  @moduledoc """
  Checklist item tied to a launch task.
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

    attribute :description, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :completed, :boolean do
      allow_nil?(false)
      default(false)
      public?(true)
    end

    attribute :task_id, :uuid do
      allow_nil?(false)
      public?(true)
    end
  end

  relationships do
    belongs_to :task, AshScenario.Examples.Task do
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
      accept([:description, :completed, :task_id, :organization_id])
    end

    update :update do
      primary?(true)
      accept([:description, :completed])
    end
  end

  prototypes do
    prototype :review_copy do
      attr(:description, "Review release notes copy")
      attr(:task_id, :draft_release_notes)
      attr(:organization_id, :acme_corp)
      attr(:completed, false)
    end

    prototype :legal_signoff do
      attr(:description, "Collect legal sign-off")
      attr(:task_id, :draft_release_notes)
      attr(:organization_id, :acme_corp)
      attr(:completed, false)
    end
  end
end
