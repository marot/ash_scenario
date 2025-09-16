defmodule AshScenario.Scenario.Executor.DatabaseStrategy do
  @moduledoc """
  Execution strategy for creating resources with database persistence.

  This strategy uses Ash.create to persist resources to the database
  and wraps execution in a transaction for atomicity.
  """

  @behaviour AshScenario.Scenario.Executor

  alias AshScenario.Log
  alias AshScenario.Scenario.Helpers

  @impl true
  def create_resource(resource_module, attributes, opts) do
    action = Keyword.get(opts, :action, :create)
    domain = Keyword.get(opts, :domain)
    explicit_nil_keys = Keyword.get(opts, :__explicit_nil_keys__, [])

    with {:ok, create_action} <- Helpers.get_create_action(resource_module, action),
         {:ok, changeset, tenant_value} <-
           Helpers.build_changeset(
             resource_module,
             create_action,
             attributes,
             Keyword.put(opts, :__explicit_nil_keys__, explicit_nil_keys)
           ) do
      create_opts = AshScenario.Multitenancy.add_tenant_to_opts([domain: domain], tenant_value)

      Ash.create(changeset, create_opts)
    end
  end

  @impl true
  def wrap_execution(ordered_prototypes, opts, execution_fn) do
    {_opts, trace} = Log.ensure_trace(opts)

    transaction_resources =
      ordered_prototypes
      |> Enum.map(& &1.resource)
      |> Enum.uniq()

    Log.debug(
      fn ->
        "transaction_start resources=#{inspect(transaction_resources)}"
      end,
      component: :runner,
      trace_id: trace
    )

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
