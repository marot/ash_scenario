defmodule Validated do
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

  @moduledoc """
  Minimal resource to exercise absent()/present() validations interaction.
  Only necessary fields are included.
  """

  attributes do
    uuid_primary_key :id

    attribute :date, :date do
      allow_nil? false
      public? true
    end

    attribute :custom_name, :string do
      allow_nil? true
      public? true
    end

    attribute :custom_description, :string do
      allow_nil? true
      public? true
    end

    attribute :planned_start_time, :time do
      allow_nil? true
      public? true
    end

    attribute :planned_end_time, :time do
      allow_nil? true
      public? true
    end
  end

  # Keep this minimal: treat activity_library_id as a plain attribute
  # to avoid cross-resource dependencies in tests.
  attributes do
    attribute :activity_library_id, :string do
      allow_nil? true
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :date,
        :activity_library_id,
        :custom_name,
        :custom_description,
        :planned_start_time,
        :planned_end_time
      ]
    end

    update :update do
      primary? true

      accept [
        :activity_library_id,
        :custom_name,
        :custom_description,
        :planned_start_time,
        :planned_end_time
      ]
    end
  end

  validations do
    #   # Either library activity OR both custom fields
    validate present([:activity_library_id]) do
      where [absent(:custom_name), absent(:custom_description)]
      message "must have either activity_library_id or both custom_name and custom_description"
    end

    validate present([:custom_name, :custom_description]) do
      where absent(:activity_library_id)
      message "must have both custom_name and custom_description when not using library activity"
    end

    validate present([:planned_end_time]), where: [present(:planned_start_time)]
    # End must be after start
    validate compare(:planned_end_time, greater_than: :planned_start_time) do
      where present([:planned_start_time, :planned_end_time])
    end
  end

  prototypes do
    prototype :library_activity do
      attr(:date, ~D[2024-07-15])
      attr(:activity_library_id, "lib-1")
      attr(:planned_start_time, ~T[10:00:00])
      attr(:planned_end_time, ~T[11:00:00])
    end

    prototype :custom_activity do
      attr(:date, ~D[2024-07-15])
      attr(:custom_name, "Custom")
      attr(:custom_description, "Desc")
      attr(:planned_start_time, ~T[15:00:00])
      attr(:planned_end_time, ~T[16:00:00])
    end
  end
end
