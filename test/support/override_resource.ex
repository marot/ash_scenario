defmodule OverrideResource do
  @moduledoc false
  use Ash.Resource,
    domain: Domain,
    extensions: [AshScenario.Dsl]

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name]
    end

    create :alternate do
      accept [:name]
      change set_attribute(:name, "alternate")
    end
  end

  prototypes do
    prototype :default_behavior do
      attr(:name, "default")
    end

    prototype :function_override do
      attr(:name, "should not insert")

      create do
        function {__MODULE__, :always_fail, []}
      end
    end

    prototype :action_override do
      attr(:name, "ignored")

      create do
        action :alternate
      end
    end
  end

  def always_fail(_attrs, _opts), do: {:error, :boom}
end
