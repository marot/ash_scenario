defmodule Mix.Tasks.AshScenario.Css.Status do
  @moduledoc """
  Checks the status of the AshScenario Tailwind CSS compilation.

  ## Usage

      mix ash_scenario.css.status

  This task will report:
  - Whether CSS is compiled and embedded
  - The size of the compiled CSS
  - When to rebuild if files have changed
  """
  @shortdoc "Check AshScenario CSS compilation status"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("AshScenario CSS Status")
    Mix.shell().info("=" |> String.duplicate(50))

    css_path = Path.join(["priv", "static", "ash_scenario.css"])
    source_path = Path.join(["assets", "css", "ash_scenario.css"])

    cond do
      not File.exists?(source_path) ->
        Mix.shell().error("❌ Source CSS file not found: #{source_path}")
        Mix.shell().info("")
        Mix.shell().info("To set up Tailwind CSS:")
        Mix.shell().info("  1. Create #{source_path}")
        Mix.shell().info("  2. Add Tailwind imports and source directives")
        Mix.shell().info("  3. Run: mix tailwind ash_scenario")

      not File.exists?(css_path) ->
        Mix.shell().error("❌ CSS not compiled")
        Mix.shell().info("")
        Mix.shell().info("To compile CSS, run:")
        Mix.shell().info("  mix tailwind ash_scenario")
        Mix.shell().info("")
        Mix.shell().info("For production build:")
        Mix.shell().info("  mix tailwind ash_scenario --minify")

      true ->
        css_stat = File.stat!(css_path)
        source_stat = File.stat!(source_path)

        # Check if we have the Assets module loaded
        assets_available = Code.ensure_loaded?(AshScenario.Tailwind.Assets)

        Mix.shell().info("✅ CSS is compiled")
        Mix.shell().info("")
        Mix.shell().info("Details:")
        Mix.shell().info("  Output: #{css_path}")
        Mix.shell().info("  Size: #{format_bytes(css_stat.size)}")
        Mix.shell().info("  Modified: #{format_time(css_stat.mtime)}")

        if assets_available do
          if AshScenario.Tailwind.Assets.available?() do
            Mix.shell().info("  Embedded: ✅ Yes (available at compile time)")
          else
            Mix.shell().warning("  Embedded: ⚠️  No (recompile the library)")
          end
        end

        Mix.shell().info("")

        # Check if source is newer than compiled
        if DateTime.compare(
             datetime_from_erlang(source_stat.mtime),
             datetime_from_erlang(css_stat.mtime)
           ) == :gt do
          Mix.shell().warning("⚠️  Source CSS is newer than compiled CSS")
          Mix.shell().info("To rebuild, run: mix tailwind ash_scenario")
        else
          Mix.shell().info("ℹ️  CSS is up to date")
        end

        # Check for Tailwind classes in files
        check_tailwind_usage()
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_time({{year, month, day}, {hour, minute, second}}) do
    "#{year}-#{pad(month)}-#{pad(day)} #{pad(hour)}:#{pad(minute)}:#{pad(second)}"
  end

  defp pad(num), do: String.pad_leading("#{num}", 2, "0")

  defp datetime_from_erlang({{year, month, day}, {hour, minute, second}}) do
    {:ok, datetime} =
      DateTime.new(
        Date.new!(year, month, day),
        Time.new!(hour, minute, second)
      )

    datetime
  end

  defp check_tailwind_usage do
    lib_path = Path.join(["lib", "ash_scenario", "**", "*.ex"])
    files = Path.wildcard(lib_path)

    # Common Tailwind class patterns
    patterns = [
      ~r/class="[^"]*(?:bg-|text-|p-|m-|flex|grid|rounded|border|shadow)/,
      ~r/class: "[^"]*(?:bg-|text-|p-|m-|flex|grid|rounded|border|shadow)/
    ]

    files_with_tailwind =
      files
      |> Enum.filter(fn file ->
        content = File.read!(file)
        Enum.any?(patterns, &Regex.match?(&1, content))
      end)

    if length(files_with_tailwind) > 0 do
      Mix.shell().info("")
      Mix.shell().info("Files using Tailwind classes (#{length(files_with_tailwind)}):")

      files_with_tailwind
      |> Enum.take(5)
      |> Enum.each(fn file ->
        relative_path = Path.relative_to_cwd(file)
        Mix.shell().info("  • #{relative_path}")
      end)

      if length(files_with_tailwind) > 5 do
        Mix.shell().info("  ... and #{length(files_with_tailwind) - 5} more")
      end
    end
  end
end
