defmodule AshScenario.Log do
  @moduledoc """
  Lightweight logging helpers for consistent, high‑quality debug output.

  - Adds consistent metadata (`:component`, `:resource`, `:ref`, `:trace_id`).
  - Functions mirror `Logger.*` to keep usage simple.
  - Honors global Logger level/config; use `config/test.exs` to enable debug.
  """

  require Logger

  @type meta :: keyword()

  @spec with(metadata :: meta(), fun :: (-> any())) :: any()
  def with(metadata, fun) when is_function(fun, 0) do
    prev = Logger.metadata()

    try do
      Logger.metadata(metadata)
      fun.()
    after
      Logger.metadata(prev)
    end
  end

  @spec debug(message :: String.t() | (-> iodata()), meta()) :: :ok
  def debug(message, meta \\ []), do: Logger.debug(message, meta)

  @spec info(message :: String.t() | (-> iodata()), meta()) :: :ok
  def info(message, meta \\ []), do: Logger.info(message, meta)

  @spec warn(message :: String.t() | (-> iodata()), meta()) :: :ok
  def warn(message, meta \\ []), do: Logger.warning(message, meta)

  @spec error(message :: String.t() | (-> iodata()), meta()) :: :ok
  def error(message, meta \\ []), do: Logger.error(message, meta)

  @doc """
  Ensure a `trace_id` exists in opts. Returns `{opts_with_trace, trace_id}`.
  """
  @spec ensure_trace(keyword()) :: {keyword(), String.t()}
  def ensure_trace(opts) do
    case Keyword.get(opts, :trace_id) do
      nil ->
        trace = new_trace_id()
        {Keyword.put(opts, :trace_id, trace), trace}

      trace ->
        {opts, trace}
    end
  end

  @spec new_trace_id() :: String.t()
  def new_trace_id do
    uniq = :erlang.unique_integer([:positive, :monotonic])
    <<high::64, low::64>> = :crypto.strong_rand_bytes(16)
    :io_lib.format("~16.16.0b-~.16b-~.16b", [uniq, high, low]) |> IO.iodata_to_binary()
  end
end
