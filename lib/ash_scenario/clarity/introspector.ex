if Code.ensure_loaded?(Clarity.Introspector) do
  defmodule AshScenario.Clarity.Introspector do
    @moduledoc """
    Clarity integration for AshScenario prototypes.

    When this module is added to the `:clarity_introspectors` configuration it
    augments Ash resource pages with an extra "Prototypes" tab. From there you
    can trigger prototype creation directly inside Clarity using
    `AshScenario.run/2`.
    """

    @behaviour Clarity.Introspector

    alias AshScenario.Info
    alias Clarity.Vertex

    @impl Clarity.Introspector
    def dependencies do
      [Clarity.Introspector.Ash.Domain]
    end

    @impl Clarity.Introspector
    def introspect(graph) do
      for %Vertex.Ash.Resource{resource: resource} = resource_vertex <- :digraph.vertices(graph),
          Info.has_prototypes?(resource) do
        attach_prototype_content(graph, resource_vertex, resource)
      end

      graph
    end

    defp attach_prototype_content(graph, resource_vertex, resource) do
      content_vertex = %Vertex.Content{
        id: "ash_scenario_prototypes:#{inspect(resource)}",
        name: "Prototypes",
        content:
          {:live_view,
           {AshScenario.Clarity.PrototypeLive,
            %{
              "resource" => Atom.to_string(resource)
            }}}
      }

      :digraph.add_vertex(graph, content_vertex, Vertex.unique_id(content_vertex))
      :digraph.add_edge(graph, resource_vertex, content_vertex, :content)
    end
  end
end
