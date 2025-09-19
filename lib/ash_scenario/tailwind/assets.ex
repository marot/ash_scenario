if Code.ensure_loaded?(Tailwind) do
  defmodule AshScenario.Tailwind.Assets do
    @moduledoc """
    Asset management for optional Tailwind CSS integration.
    Only available when Tailwind dependency is present.
    """

    # Embed CSS at compile time
    @external_resource "priv/static/ash_scenario.css"
    @css_content (if File.exists?("priv/static/ash_scenario.css") do
                    File.read!("priv/static/ash_scenario.css")
                  else
                    nil
                  end)

    # Generate a hash for cache busting
    @css_hash (if @css_content do
                 :crypto.hash(:md5, @css_content)
                 |> Base.encode16()
                 |> String.downcase()
                 |> String.slice(0..7)
               else
                 nil
               end)

    @doc """
    Returns the compiled CSS content if available.

    Returns `{:ok, content}` if CSS is compiled and embedded, or
    `{:error, :not_compiled}` with helpful instructions otherwise.
    """
    def css_content do
      if @css_content do
        {:ok, @css_content}
      else
        {:error, :not_compiled}
      end
    end

    @doc """
    Returns a hash of the CSS content for cache busting.
    Returns nil if CSS is not compiled.
    """
    def css_hash, do: @css_hash

    @doc """
    Returns the path to the compiled CSS file in the application's priv directory.
    """
    def css_path do
      Path.join(:code.priv_dir(:ash_scenario), "static/ash_scenario.css")
    end

    @doc """
    Builds the CSS if in development mode.
    """
    def build_css do
      if Mix.env() != :prod do
        System.cmd("mix", ["tailwind", "ash_scenario", "--minify"])
      else
        {:error, :production_mode}
      end
    end

    @doc """
    Returns a Phoenix.HTML style tag with the compiled CSS.
    Useful for injecting CSS into LiveView components.
    """
    def style_tag do
      case css_content() do
        {:ok, content} ->
          Phoenix.HTML.raw("""
          <style>
          /* AshScenario Tailwind CSS */
          #{content}
          </style>
          """)

        {:error, :not_compiled} ->
          if Mix.env() == :dev do
            Phoenix.HTML.raw("""
            <!-- AshScenario CSS not compiled.
                 Run: mix tailwind ash_scenario
                 or: mix ash_scenario.css.status for details -->
            """)
          else
            Phoenix.HTML.raw("")
          end
      end
    end

    @doc """
    Returns a link tag pointing to the compiled CSS file.
    Useful when serving the CSS as a static asset.
    Includes cache busting via version parameter.
    """
    def link_tag(opts \\ []) do
      path = Keyword.get(opts, :path, "/ash_scenario/css/ash_scenario.css")

      # Add cache busting hash if available
      path_with_version =
        if @css_hash do
          "#{path}?v=#{@css_hash}"
        else
          path
        end

      Phoenix.HTML.raw("""
      <link rel="stylesheet" href="#{path_with_version}" />
      """)
    end

    @doc """
    Checks if Tailwind CSS has been compiled.
    """
    def compiled? do
      @css_content != nil
    end

    @doc """
    Injects the AshScenario Tailwind CSS into the current page if available.

    Use this in your LiveView or component when you want to include the styles:

        <%= AshScenario.Tailwind.Assets.inject() %>

    Or with a custom path:

        <%= AshScenario.Tailwind.Assets.inject(path: "/assets/ash_scenario.css") %>
    """
    def inject(opts \\ []) do
      if Keyword.get(opts, :inline, false) do
        style_tag()
      else
        link_tag(opts)
      end
    end

    @doc """
    Checks if Tailwind CSS is available and compiled.

    Returns `true` if CSS has been compiled and embedded, `false` otherwise.
    In development, logs a warning if CSS is not compiled.
    """
    def available? do
      result = compiled?()

      if not result and Mix.env() == :dev do
        IO.warn("""
        AshScenario Tailwind CSS is not compiled.
        To compile CSS, run: mix tailwind ash_scenario
        For status details: mix ash_scenario.css.status
        """)
      end

      result
    end

    @doc """
    Returns CSS classes with fallback when Tailwind is not available.

    ## Examples

        # Returns Tailwind classes when available, fallback otherwise
        AshScenario.Tailwind.Assets.classes(
          "bg-blue-500 text-white px-4 py-2 rounded",
          fallback: "default-button-class"
        )
    """
    def classes(tailwind_classes, opts \\ []) do
      if available?() do
        tailwind_classes
      else
        Keyword.get(opts, :fallback, "")
      end
    end
  end
end
