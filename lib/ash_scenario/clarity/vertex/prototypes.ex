if Code.ensure_loaded?(Clarity) do
  defmodule AshScenario.Clarity.Vertex.Prototypes do
    @moduledoc false

    @type t() :: %__MODULE__{}
    defstruct []

    defimpl Clarity.Vertex do
      @impl Clarity.Vertex
      def unique_id(_vertex), do: "ash_scenario:prototypes"

      @impl Clarity.Vertex
      def graph_id(_vertex), do: "ash_scenario_prototypes"

      @impl Clarity.Vertex
      def graph_group(_vertex), do: ["AshScenario"]

      @impl Clarity.Vertex
      def type_label(_vertex), do: "AshScenario.Prototypes"

      @impl Clarity.Vertex
      def render_name(_vertex), do: "All Prototypes"

      @impl Clarity.Vertex
      def dot_shape(_vertex), do: "folder"

      @impl Clarity.Vertex
      def markdown_overview(_vertex) do
        """
        # AshScenario Prototypes

        Central hub for managing all prototype data generation across your application.

        **Features:**
        - View all resources with defined prototypes
        - Execute prototypes in bulk
        - Navigate to specific resource prototype pages
        """
      end
    end
  end
end
