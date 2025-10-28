defmodule AshScenario.MFAEvaluationTest do
  @moduledoc """
  Tests for MFA (Module-Function-Args) tuple evaluation in prototype attributes.

  Tests the feature through the public API by creating actual prototypes.
  """
  use ExUnit.Case

  defmodule TestHelpers do
    def static_value, do: "static"
    def unique_email(i), do: "user#{i}@example.com"
    def contextual(i, ctx), do: "#{ctx.prototype_ref}_#{i}"
    def with_prefix(prefix, i), do: "#{prefix}#{i}"
  end

  defmodule TestResource do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshScenario.Dsl]

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id

      attribute :email, :string do
        public? true
      end

      attribute :username, :string do
        public? true
      end

      attribute :code, :string do
        public? true
      end
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:email, :username, :code]
      end
    end

    prototypes do
      prototype :static_mfa do
        attr :email, {TestHelpers, :static_value, []}
        attr :username, "regular_value"
      end

      prototype :sequence_mfa do
        attr :email, {TestHelpers, :unique_email, []}
      end

      prototype :contextual_mfa do
        attr :username, {TestHelpers, :contextual, []}
      end

      prototype :with_args_mfa do
        attr :code, {TestHelpers, :with_prefix, ["CODE_"]}
      end

      prototype :system_unique do
        attr :username, {System, :unique_integer, [[:positive]]}
      end
    end
  end

  defmodule TestDomain do
    use Ash.Domain

    resources do
      resource TestResource
    end
  end

  setup do
    AshScenario.Sequence.reset()
    :ok
  end

  describe "MFA tuple evaluation in prototypes" do
    test "arity 0: static function" do
      {:ok, resources} = AshScenario.run([{TestResource, :static_mfa}], strategy: :struct)

      resource = resources[{TestResource, :static_mfa}]
      assert resource.email == "static"
      assert resource.username == "regular_value"
    end

    test "arity 1: function with sequence index" do
      {:ok, resources1} = AshScenario.run([{TestResource, :sequence_mfa}], strategy: :struct)
      {:ok, resources2} = AshScenario.run([{TestResource, :sequence_mfa}], strategy: :struct)

      resource1 = resources1[{TestResource, :sequence_mfa}]
      resource2 = resources2[{TestResource, :sequence_mfa}]

      assert resource1.email == "user0@example.com"
      assert resource2.email == "user1@example.com"
    end

    test "arity 2: function with index and context" do
      {:ok, resources} = AshScenario.run([{TestResource, :contextual_mfa}], strategy: :struct)

      resource = resources[{TestResource, :contextual_mfa}]
      assert resource.username == "contextual_mfa_0"
    end

    test "with extra args from tuple" do
      {:ok, resources} = AshScenario.run([{TestResource, :with_args_mfa}], strategy: :struct)

      resource = resources[{TestResource, :with_args_mfa}]
      assert resource.code == "CODE_0"
    end

    test "System.unique_integer works" do
      {:ok, resources1} = AshScenario.run([{TestResource, :system_unique}], strategy: :struct)
      {:ok, resources2} = AshScenario.run([{TestResource, :system_unique}], strategy: :struct)

      resource1 = resources1[{TestResource, :system_unique}]
      resource2 = resources2[{TestResource, :system_unique}]

      assert is_integer(resource1.username)
      assert is_integer(resource2.username)
      assert resource1.username != resource2.username
    end

    test "sequences increment across multiple runs" do
      {:ok, resources1} = AshScenario.run([{TestResource, :sequence_mfa}], strategy: :struct)
      {:ok, resources2} = AshScenario.run([{TestResource, :sequence_mfa}], strategy: :struct)
      {:ok, resources3} = AshScenario.run([{TestResource, :sequence_mfa}], strategy: :struct)

      resource1 = resources1[{TestResource, :sequence_mfa}]
      resource2 = resources2[{TestResource, :sequence_mfa}]
      resource3 = resources3[{TestResource, :sequence_mfa}]

      # Same attribute across runs increments the sequence
      assert resource1.email == "user0@example.com"
      assert resource2.email == "user1@example.com"
      assert resource3.email == "user2@example.com"
    end
  end

  describe "AshScenario.Sequence" do
    test "next/1 returns incrementing values" do
      assert AshScenario.Sequence.next(:test) == 0
      assert AshScenario.Sequence.next(:test) == 1
      assert AshScenario.Sequence.next(:test) == 2
    end

    test "different keys have independent sequences" do
      assert AshScenario.Sequence.next(:key1) == 0
      assert AshScenario.Sequence.next(:key2) == 0
      assert AshScenario.Sequence.next(:key1) == 1
      assert AshScenario.Sequence.next(:key2) == 1
    end

    test "reset/0 clears all sequences" do
      AshScenario.Sequence.next(:test)
      AshScenario.Sequence.next(:test)
      assert AshScenario.Sequence.next(:test) == 2

      AshScenario.Sequence.reset()

      assert AshScenario.Sequence.next(:test) == 0
    end
  end
end
