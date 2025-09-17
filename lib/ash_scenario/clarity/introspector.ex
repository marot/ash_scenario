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

  def dependencies do
    [Clarity.Introspector.Ash.Domain, Clarity.Introspector.Root]
  end

  @impl Clarity.Introspector
  def introspect(graph) do
    # Add global prototypes vertex attached to root
    for %Vertex.Root{} = root_vertex <- :digraph.vertices(graph) do
      attach_global_prototypes(graph, root_vertex)
    end

    # Add per-resource prototype pages
    for %Vertex.Ash.Resource{resource: resource} = resource_vertex <- :digraph.vertices(graph),
        Info.has_prototypes?(resource) do
      attach_prototype_content(graph, resource_vertex, resource)
    end

    graph
  end

  defp attach_global_prototypes(graph, root_vertex) do
    # Create the global prototypes vertex
    prototypes_vertex = %AshScenario.Clarity.Vertex.Prototypes{}
    :digraph.add_vertex(graph, prototypes_vertex, Vertex.unique_id(prototypes_vertex))
    :digraph.add_edge(graph, root_vertex, prototypes_vertex, :prototypes)

    # Attach the dashboard as content to the global prototypes vertex
    dashboard_content = %Vertex.Content{
      id: "ash_scenario_prototypes_dashboard",
      name: "Dashboard",
      content: {:live_view, {AshScenario.Clarity.PrototypesDashboardLive, %{}}}
    }

    :digraph.add_vertex(graph, dashboard_content, Vertex.unique_id(dashboard_content))
    :digraph.add_edge(graph, prototypes_vertex, dashboard_content, :content)
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
