defmodule TransactionResource do
  @moduledoc false
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Mnesia,
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
  end

  mnesia do
    table :transaction_resources
  end

  prototypes do
    prototype :ok_entry do
      attr(:name, "should_rollback")
    end

    prototype :failing_entry do
      create do
        function {__MODULE__, :always_fail, []}
      end
    end
  end

  def always_fail(_attrs, _opts), do: {:error, :forced_failure}
end
