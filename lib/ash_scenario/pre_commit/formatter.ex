defmodule AshScenario.PreCommit.Formatter do
  @moduledoc """
  Pre-commit hook module that formats only staged Elixir files.
  """

  @doc """
  Formats only the staged Elixir files and re-adds them to staging.

  Returns `:ok` if all files are formatted successfully, or `{:error, reason}` if any step fails.
  """
  def run(_args \\ []) do
    with {:ok, staged_files} <- get_staged_files(),
         elixir_files <- filter_elixir_files(staged_files),
         :ok <- format_files(elixir_files),
         :ok <- restage_files(elixir_files) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_staged_files do
    case System.cmd("git", ["diff", "--cached", "--name-only", "--diff-filter=d"]) do
      {output, 0} ->
        files =
          output
          |> String.trim()
          |> String.split("\n", trim: true)

        {:ok, files}

      {error, _} ->
        {:error, "Failed to get staged files: #{error}"}
    end
  end

  defp filter_elixir_files(files) do
    Enum.filter(files, fn file ->
      String.ends_with?(file, [".ex", ".exs", ".heex"])
    end)
  end

  defp format_files([]), do: :ok

  defp format_files(files) do
    case System.cmd("mix", ["format", "--"] ++ files, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {error, _} -> {:error, "Failed to format files: #{error}"}
    end
  end

  defp restage_files([]), do: :ok

  defp restage_files(files) do
    case System.cmd("git", ["add"] ++ files) do
      {_output, 0} -> :ok
      {error, _} -> {:error, "Failed to restage files: #{error}"}
    end
  end
end
