defmodule AshScenario.MultitenancyTest do
  use ExUnit.Case, async: true

  # Test resources with multitenancy
  defmodule Organization do
    use Ash.Resource,
      domain: AshScenario.MultitenancyTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshScenario.Dsl]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read]

      create :create do
        accept [:name]
      end
    end

    prototypes do
      prototype :test_org do
        attr(:name, "Test Organization")
      end
    end
  end

  defmodule TenantPost do
    use Ash.Resource,
      domain: AshScenario.MultitenancyTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshScenario.Dsl]

    # Configure attribute-based multitenancy
    multitenancy do
      strategy :attribute
      attribute :organization_id
    end

    attributes do
      uuid_primary_key :id
      attribute :title, :string, allow_nil?: false, public?: true
      attribute :content, :string, public?: true
    end

    relationships do
      belongs_to :organization, Organization, public?: true
    end

    actions do
      defaults [:read]

      create :create do
        accept [:title, :content, :organization_id]
      end
    end

    prototypes do
      prototype :tenant_post do
        attr(:title, "Test Post")
        attr(:content, "Post content")
        attr(:organization_id, :test_org)
      end

      prototype :standalone_post do
        attr(:title, "Standalone Post")
        attr(:content, "No org reference")
      end
    end
  end

  defmodule NonTenantPost do
    use Ash.Resource,
      domain: AshScenario.MultitenancyTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshScenario.Dsl]

    attributes do
      uuid_primary_key :id
      attribute :title, :string, allow_nil?: false, public?: true
      attribute :content, :string, public?: true
    end

    relationships do
      belongs_to :organization, Organization, public?: true
    end

    actions do
      defaults [:read]

      create :create do
        accept [:title, :content, :organization_id]
      end
    end

    prototypes do
      prototype :regular_post do
        attr(:title, "Regular Post")
        attr(:content, "Regular content")
        attr(:organization_id, :test_org)
      end
    end
  end

  defmodule Domain do
    use Ash.Domain

    resources do
      resource Organization
      resource TenantPost
      resource NonTenantPost
    end
  end

  setup do
    # Start the scenario registry if not already started
    case start_supervised(AshScenario.Scenario.Registry) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Register our test resources
    AshScenario.register_prototypes(Organization)
    AshScenario.register_prototypes(TenantPost)
    AshScenario.register_prototypes(NonTenantPost)

    :ok
  end

  describe "multitenancy detection" do
    test "detects attribute-based multitenancy" do
      assert AshScenario.Multitenancy.has_multitenancy?(TenantPost)
      assert AshScenario.Multitenancy.has_attribute_multitenancy?(TenantPost)
      assert AshScenario.Multitenancy.multitenancy_strategy(TenantPost) == :attribute
      assert AshScenario.Multitenancy.tenant_attribute(TenantPost) == :organization_id
    end

    test "detects absence of multitenancy" do
      refute AshScenario.Multitenancy.has_multitenancy?(NonTenantPost)
      refute AshScenario.Multitenancy.has_attribute_multitenancy?(NonTenantPost)
      assert AshScenario.Multitenancy.multitenancy_strategy(NonTenantPost) == nil
      assert AshScenario.Multitenancy.tenant_attribute(NonTenantPost) == nil
    end

    test "extracts tenant info from attributes" do
      attrs = %{title: "Test", content: "Content", organization_id: "org-123"}

      {:ok, tenant, clean} = AshScenario.Multitenancy.extract_tenant_info(TenantPost, attrs)
      assert tenant == "org-123"
      assert clean == %{title: "Test", content: "Content"}
      refute Map.has_key?(clean, :organization_id)
    end

    test "returns unchanged attributes for non-tenant resources" do
      attrs = %{title: "Test", content: "Content", organization_id: "org-123"}

      {:ok, tenant, clean} = AshScenario.Multitenancy.extract_tenant_info(NonTenantPost, attrs)
      assert tenant == nil
      assert clean == attrs
    end
  end

  describe "prototype creation with multitenancy" do
    test "creates tenant resource with organization reference" do
      # This should automatically:
      # 1. Create the organization
      # 2. Extract organization_id as tenant
      # 3. Pass it via tenant: option to Ash.create
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {TenantPost, :tenant_post}
          ],
          domain: Domain
        )

      post = resources[{TenantPost, :tenant_post}]
      org = resources[{Organization, :test_org}]

      assert post.title == "Test Post"
      assert post.content == "Post content"
      assert post.organization_id == org.id

      # Verify we can read it back with tenant
      {:ok, [found]} = Ash.read(TenantPost, tenant: org.id, domain: Domain)
      assert found.id == post.id
    end

    test "creates non-tenant resource with organization reference" do
      # This should work normally without tenant extraction
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {NonTenantPost, :regular_post}
          ],
          domain: Domain
        )

      post = resources[{NonTenantPost, :regular_post}]
      org = resources[{Organization, :test_org}]

      assert post.title == "Regular Post"
      assert post.organization_id == org.id

      # Can read without tenant since no multitenancy
      {:ok, [found]} = Ash.read(NonTenantPost, domain: Domain)
      assert found.id == post.id
    end

    test "handles tenant resource without organization reference" do
      # Should fail when trying to create a tenant resource without providing a tenant
      # This is correct behavior - tenant resources require a tenant unless global?: true
      assert {:error, reason} =
               AshScenario.run_prototype(TenantPost, :standalone_post, domain: Domain)

      # The error should be about missing tenant
      assert reason =~ "TenantRequired" or reason =~ "tenant"
    end

    test "creates multiple tenant resources with dependencies" do
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {Organization, :test_org},
            {TenantPost, :tenant_post}
          ],
          domain: Domain
        )

      org = resources[{Organization, :test_org}]
      post = resources[{TenantPost, :tenant_post}]

      assert post.organization_id == org.id
    end
  end

  describe "overrides with multitenancy" do
    test "overrides work with tenant resources" do
      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {TenantPost, :tenant_post, %{title: "Overridden Title"}}
          ],
          domain: Domain
        )

      post = resources[{TenantPost, :tenant_post}]
      assert post.title == "Overridden Title"
      # Original value
      assert post.content == "Post content"
    end

    test "can override tenant attribute" do
      # Create an org first
      {:ok, org} = AshScenario.run_prototype(Organization, :test_org, domain: Domain)

      # Override the tenant attribute directly
      {:ok, post} =
        AshScenario.run_prototype(
          TenantPost,
          :standalone_post,
          domain: Domain,
          overrides: %{organization_id: org.id}
        )

      assert post.organization_id == org.id
    end
  end

  describe "custom functions with multitenancy" do
    defmodule CustomFactory do
      def create_tenant_post(attributes, opts) do
        # Custom function should receive tenant in opts
        tenant = Keyword.get(opts, :tenant)

        if tenant do
          # Simulate custom creation with tenant awareness
          struct = %TenantPost{
            id: Ash.UUID.generate(),
            title: attributes[:title] || "Custom Title",
            content: attributes[:content] || "Custom Content",
            organization_id: tenant
          }

          {:ok, struct}
        else
          {:error, "No tenant provided"}
        end
      end
    end

    defmodule TenantPostWithCustom do
      use Ash.Resource,
        domain: nil,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshScenario.Dsl]

      multitenancy do
        strategy :attribute
        attribute :organization_id
      end

      attributes do
        uuid_primary_key :id
        attribute :title, :string, public?: true
        attribute :content, :string, public?: true
        timestamps()
      end

      relationships do
        belongs_to :organization, Organization, public?: true
      end

      actions do
        defaults [:read]

        create :create do
          accept [:title, :content, :organization_id]
        end
      end

      prototypes do
        create function: {CustomFactory, :create_tenant_post, []}

        prototype :custom_post do
          attr(:title, "Custom Post")
          attr(:organization_id, :test_org)
        end
      end
    end

    defmodule CustomDomain do
      use Ash.Domain

      resources do
        resource Organization
        resource TenantPostWithCustom
      end
    end

    test "custom functions receive tenant in opts" do
      # Register the resource with custom function
      AshScenario.register_prototypes(TenantPostWithCustom)

      {:ok, resources} =
        AshScenario.run_prototypes(
          [
            {TenantPostWithCustom, :custom_post}
          ],
          domain: CustomDomain
        )

      post = resources[{TenantPostWithCustom, :custom_post}]
      org = resources[{Organization, :test_org}]

      assert post.title == "Custom Post"
      assert post.organization_id == org.id
    end
  end

  describe "struct builder with multitenancy" do
    test "creates structs with tenant attributes" do
      {:ok, resources} =
        AshScenario.create_structs([
          {TenantPost, :tenant_post}
        ])

      post = resources[{TenantPost, :tenant_post}]
      org = resources[{Organization, :test_org}]

      assert post.title == "Test Post"
      # For struct builder, relationships are kept as structs, not IDs
      assert post.organization_id == org
      assert %TenantPost{} = post
      assert %Organization{} = org
    end
  end
end
