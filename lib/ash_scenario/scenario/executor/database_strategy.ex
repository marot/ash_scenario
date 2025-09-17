defmodule AshScenario.Scenario.Executor.DatabaseStrategy do
  @moduledoc """
  Execution strategy for creating resources with database persistence.

  This strategy uses Ash.create to persist resources to the database
  and wraps execution in a transaction for atomicity.
  """

  @behaviour AshScenario.Scenario.Executor

  alias AshScenario.Scenario.Helpers

  @impl true
  def create_resource(resource_module, attributes, opts) do
    action = Keyword.get(opts, :action, :create)
    domain = Keyword.get(opts, :domain)
    explicit_nil_keys = Keyword.get(opts, :__explicit_nil_keys__, [])

    # Extract actor and authorize? from attributes
    {actor, attributes} = Map.pop(attributes, :actor)
    # Only default authorize? to true if an actor was explicitly provided
    {authorize?, attributes} = Map.pop(attributes, :authorize?, !is_nil(actor))

    with {:ok, create_action} <- Helpers.get_create_action(resource_module, action),
         {:ok, changeset, tenant_value} <-
           Helpers.build_changeset(
             resource_module,
             create_action,
             attributes,
             Keyword.put(opts, :__explicit_nil_keys__, explicit_nil_keys)
           ) do
      create_opts =
        [domain: domain]
        |> AshScenario.Multitenancy.add_tenant_to_opts(tenant_value)
        |> maybe_add_actor(actor, authorize?)

      Ash.create(changeset, create_opts)
    end
  end

  defp maybe_add_actor(opts, nil, false) do
    # When there's no actor but authorize? is explicitly false, pass that
    Keyword.put(opts, :authorize?, false)
  end

  defp maybe_add_actor(opts, nil, _), do: opts

  defp maybe_add_actor(opts, actor, authorize?) do
    opts
    |> Keyword.put(:actor, actor)
    |> Keyword.put(:authorize?, authorize?)
  end

  @impl true
  def wrap_execution(ordered_prototypes, _opts, execution_fn) do
    transaction_resources =
      ordered_prototypes
      |> Enum.map(& &1.resource)
      |> Enum.uniq()

    transaction_fn = fn ->
      execution_fn.()
    end

    transaction_resources
    |> Ash.transaction(transaction_fn)
    |> case do
      {:ok, result} ->
        result

      {:error, reason} ->
        {:error, reason}
    end
  end
end
