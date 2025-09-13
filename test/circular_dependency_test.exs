defmodule TestDomain do
  use Ash.Domain
  
  resources do
    allow_unregistered? true
  end
end

defmodule CircularDependencyTest do
  use ExUnit.Case
  alias AshScenario.Scenario.Registry

  setup do
    # Start the Registry if not already started
    case Process.whereis(Registry) do
      nil -> Registry.start_link()
      _pid -> :ok
    end

    # Clear any existing prototypes
    Registry.clear_all()
    :ok
  end

  describe "runtime circular dependency detection" do
    test "detects self-referential dependencies (A → A)" do
      defmodule SelfRefResource do
        use Ash.Resource,
          domain: TestDomain,
          extensions: [AshScenario.Dsl]

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        relationships do
          belongs_to :parent, __MODULE__, public?: true
        end

        actions do
          defaults [:read]
          create :create do
            accept [:name, :parent_id]
          end
        end

        prototypes do
          prototype :self_ref do
            attr :name, "Self Reference"
            attr :parent_id, :self_ref  # Points to itself
          end
        end
      end

      assert {:error, message} = AshScenario.register_prototypes(SelfRefResource)
      assert message =~ "Circular dependency detected"
      assert message =~ "self_ref"
    end

    test "detects direct circular dependencies within a resource (A → B → A)" do
      defmodule DirectCycleResource do
        use Ash.Resource,
          domain: TestDomain,
          extensions: [AshScenario.Dsl]

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        relationships do
          belongs_to :parent, __MODULE__, public?: true
        end

        actions do
          defaults [:read]
          create :create do
            accept [:name, :parent_id]
          end
        end

        prototypes do
          prototype :node_a do
            attr :name, "Node A"
            attr :parent_id, :node_b
          end
          
          prototype :node_b do
            attr :name, "Node B"
            attr :parent_id, :node_a  # Cycle back to A
          end
        end
      end

      assert {:error, message} = AshScenario.register_prototypes(DirectCycleResource)
      assert message =~ "Circular dependency detected"
      assert message =~ "node_a"
      assert message =~ "node_b"
    end

    test "detects indirect circular dependencies (A → B → C → A)" do
      defmodule IndirectCycleResource do
        use Ash.Resource,
          domain: TestDomain,
          extensions: [AshScenario.Dsl]

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        relationships do
          belongs_to :parent, __MODULE__, public?: true
        end

        actions do
          defaults [:read]
          create :create do
            accept [:name, :parent_id]
          end
        end

        prototypes do
          prototype :node_a do
            attr :name, "Node A"
            attr :parent_id, :node_b
          end
          
          prototype :node_b do
            attr :name, "Node B"
            attr :parent_id, :node_c
          end
          
          prototype :node_c do
            attr :name, "Node C"
            attr :parent_id, :node_a  # Cycle back to A
          end
        end
      end

      assert {:error, message} = AshScenario.register_prototypes(IndirectCycleResource)
      assert message =~ "Circular dependency detected"
    end

    test "allows valid parent-child relationships without cycles" do
      defmodule ValidHierarchyResource do
        use Ash.Resource,
          domain: TestDomain,
          extensions: [AshScenario.Dsl]

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        relationships do
          belongs_to :parent, __MODULE__, public?: true
        end

        actions do
          defaults [:read]
          create :create do
            accept [:name, :parent_id]
          end
        end

        prototypes do
          prototype :root do
            attr :name, "Root Node"
            # No parent_id - this is valid
          end
          
          prototype :child do
            attr :name, "Child Node"
            attr :parent_id, :root  # Valid reference
          end
          
          prototype :grandchild do
            attr :name, "Grandchild Node"
            attr :parent_id, :child  # Valid chain
          end
        end
      end

      assert :ok = AshScenario.register_prototypes(ValidHierarchyResource)
    end

    test "allows diamond dependency patterns without cycles" do
      defmodule DiamondPatternResource do
        use Ash.Resource,
          domain: TestDomain,
          extensions: [AshScenario.Dsl]

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        relationships do
          belongs_to :parent, __MODULE__, public?: true
          belongs_to :other_parent, __MODULE__, public?: true
        end

        actions do
          defaults [:read]
          create :create do
            accept [:name, :parent_id, :other_parent_id]
          end
        end

        prototypes do
          # Diamond pattern: root -> (left, right) -> bottom
          prototype :root do
            attr :name, "Root"
          end
          
          prototype :left do
            attr :name, "Left Branch"
            attr :parent_id, :root
          end
          
          prototype :right do
            attr :name, "Right Branch"
            attr :parent_id, :root
          end
          
          prototype :bottom do
            attr :name, "Bottom (Diamond)"
            attr :parent_id, :left
            attr :other_parent_id, :right  # Both paths lead here - still valid DAG
          end
        end
      end

      assert :ok = AshScenario.register_prototypes(DiamondPatternResource)
    end

    test "detects cross-resource circular dependencies" do
      # Clear registry before defining resources with cross-dependencies
      Registry.clear_all()

      defmodule CrossResourceA do
        use Ash.Resource,
          domain: TestDomain,
          extensions: [AshScenario.Dsl]

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        relationships do
          belongs_to :other, CircularDependencyTest.CrossResourceB, public?: true
        end

        actions do
          defaults [:read]
          create :create do
            accept [:name, :other_id]
          end
        end

        prototypes do
          prototype :instance_a do
            attr :name, "A Instance"
            attr :other_id, :instance_b
          end
        end
      end

      defmodule CrossResourceB do
        use Ash.Resource,
          domain: TestDomain,
          extensions: [AshScenario.Dsl]

        attributes do
          uuid_primary_key :id
          attribute :name, :string, public?: true
        end

        relationships do
          belongs_to :other, CircularDependencyTest.CrossResourceA, public?: true
        end

        actions do
          defaults [:read]
          create :create do
            accept [:name, :other_id]
          end
        end

        prototypes do
          prototype :instance_b do
            attr :name, "B Instance"
            attr :other_id, :instance_a
          end
        end
      end

      # Register first resource successfully
      assert :ok = AshScenario.register_prototypes(CrossResourceA)
      
      # Second registration should detect the cycle
      assert {:error, message} = AshScenario.register_prototypes(CrossResourceB)
      assert message =~ "Circular dependency detected"
    end
  end
end