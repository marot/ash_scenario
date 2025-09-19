defmodule AshScenario.Clarity.PrototypesDashboardLive do
  @moduledoc false

  use Phoenix.LiveView

  alias AshScenario.Info

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    resources_with_prototypes = find_resources_with_prototypes()
    prefix = Map.get(session, "prefix", "")

    socket =
      socket
      |> assign(
        resources: resources_with_prototypes,
        prefix: prefix,
        running: nil,
        last_result: nil,
        selected_resources: MapSet.new(),
        show_result: false
      )

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_select", %{"resource" => resource_string}, socket) do
    resource = String.to_existing_atom(resource_string)
    selected = socket.assigns.selected_resources

    new_selected =
      if MapSet.member?(selected, resource) do
        MapSet.delete(selected, resource)
      else
        MapSet.put(selected, resource)
      end

    {:noreply, assign(socket, selected_resources: new_selected)}
  end

  def handle_event("select_all", _params, socket) do
    all_resources = Enum.map(socket.assigns.resources, fn {resource, _} -> resource end)
    {:noreply, assign(socket, selected_resources: MapSet.new(all_resources))}
  end

  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, selected_resources: MapSet.new())}
  end

  def handle_event("run_selected", _params, socket) do
    resources = MapSet.to_list(socket.assigns.selected_resources)

    if Enum.empty?(resources) do
      {:noreply, put_flash(socket, :error, "No resources selected")}
    else
      socket = socket |> assign(running: :selected) |> clear_flash()

      results =
        Enum.reduce(resources, %{}, fn resource, acc ->
          case AshScenario.run_all(resource) do
            {:ok, result} -> Map.merge(acc, result)
            {:error, _reason} -> acc
          end
        end)

      socket =
        socket
        |> put_flash(
          :info,
          "Created #{map_size(results)} prototypes across #{length(resources)} resources"
        )
        |> assign(last_result: results, running: nil, show_result: true)

      {:noreply, socket}
    end
  end

  def handle_event("run_all", _params, socket) do
    all_resources = Enum.map(socket.assigns.resources, fn {resource, _} -> resource end)
    socket = socket |> assign(running: :all) |> clear_flash()

    results =
      Enum.reduce(all_resources, %{}, fn resource, acc ->
        case AshScenario.run_all(resource) do
          {:ok, result} -> Map.merge(acc, result)
          {:error, _reason} -> acc
        end
      end)

    socket =
      socket
      |> put_flash(
        :info,
        "Created #{map_size(results)} prototypes across #{length(all_resources)} resources"
      )
      |> assign(last_result: results, running: nil, show_result: true)

    {:noreply, socket}
  end

  def handle_event("toggle_result", _params, socket) do
    {:noreply, assign(socket, show_result: !socket.assigns.show_result)}
  end

  def handle_event("navigate_to_resource", %{"resource" => resource_string}, socket) do
    vertex_id = "resource:#{resource_string}"
    content_id = "ash_scenario_prototypes:#{resource_string}"
    path = Path.join([socket.assigns.prefix, vertex_id, content_id])
    {:noreply, push_patch(socket, to: path)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <%= if Code.ensure_loaded?(AshScenario.Tailwind.Assets) && AshScenario.Tailwind.Assets.available?() do %>
      <%= AshScenario.Tailwind.Assets.inject(inline: true) %>
    <% end %>
    <div class="min-h-screen bg-gradient-to-br from-base-light-50 to-base-light-100 dark:from-base-dark-900 dark:to-base-dark-800 p-8">
      <div class="max-w-7xl mx-auto">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-base-light-900 dark:text-base-dark-100 mb-2">
            AshScenario Prototypes Dashboard
          </h1>
          <p class="text-base-light-600 dark:text-base-dark-400">
            Manage prototype data generation across all resources
          </p>
        </div>

        <!-- Flash Messages -->
        <div :if={@flash && map_size(@flash) > 0} class="mb-6">
          <div :for={{kind, message} <- @flash} class={flash_class(kind)} role="alert">
            <%= message %>
          </div>
        </div>

        <!-- Action Bar -->
        <div class="mb-8 bg-white dark:bg-base-dark-900 rounded-lg shadow-sm p-6 border border-base-light-200 dark:border-base-dark-700">
          <div class="flex flex-col lg:flex-row items-start lg:items-center justify-between gap-4">
            <div class="flex-1">
              <h2 class="text-lg font-semibold text-base-light-900 dark:text-base-dark-100 mb-1">
                Batch Operations
              </h2>
              <p class="text-sm text-base-light-600 dark:text-base-dark-400">
                <%= if MapSet.size(@selected_resources) > 0 do %>
                  <%= MapSet.size(@selected_resources) %> resource(s) selected
                <% else %>
                  Select resources or run all prototypes
                <% end %>
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                class="px-4 py-2 rounded-lg text-sm font-medium border border-base-light-300 dark:border-base-dark-600 hover:bg-base-light-100 dark:hover:bg-base-dark-800 transition-colors"
                phx-click="select_all"
              >
                Select All
              </button>
              <button
                type="button"
                class="px-4 py-2 rounded-lg text-sm font-medium border border-base-light-300 dark:border-base-dark-600 hover:bg-base-light-100 dark:hover:bg-base-dark-800 transition-colors"
                phx-click="deselect_all"
              >
                Deselect All
              </button>
              <button
                type="button"
                class={[
                  "px-6 py-2 rounded-lg font-medium transition-all",
                  "bg-primary-light hover:bg-primary-light/90 text-white dark:bg-primary-dark dark:hover:bg-primary-dark/90",
                  "disabled:opacity-50 disabled:cursor-not-allowed"
                ]}
                phx-click="run_selected"
                disabled={@running != nil || MapSet.size(@selected_resources) == 0}
              >
                <%= if @running == :selected do %>
                  Running Selected...
                <% else %>
                  Run Selected
                <% end %>
              </button>
              <button
                type="button"
                class={[
                  "px-6 py-2 rounded-lg font-medium transition-all",
                  "bg-success-light hover:bg-success-light/90 text-white dark:bg-success-dark dark:hover:bg-success-dark/90",
                  "disabled:opacity-50 disabled:cursor-not-allowed"
                ]}
                phx-click="run_all"
                disabled={@running != nil}
              >
                <%= if @running == :all do %>
                  Running All...
                <% else %>
                  Run All Prototypes
                <% end %>
              </button>
            </div>
          </div>
        </div>

        <!-- Resources Grid -->
        <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <%= for {resource, prototypes} <- @resources do %>
            <div class="bg-white dark:bg-base-dark-900 rounded-lg shadow-sm hover:shadow-md transition-shadow border border-base-light-200 dark:border-base-dark-700">
              <div class="p-6">
                <div class="flex items-start justify-between mb-4">
                  <div class="flex-1">
                    <h3 class="text-lg font-semibold text-base-light-900 dark:text-base-dark-100 mb-1">
                      <%= inspect(resource) |> String.split(".") |> List.last() %>
                    </h3>
                    <p class="text-xs text-base-light-500 dark:text-base-dark-400 font-mono">
                      <%= inspect(resource) %>
                    </p>
                  </div>
                  <input
                    type="checkbox"
                    phx-click="toggle_select"
                    phx-value-resource={Atom.to_string(resource)}
                    checked={MapSet.member?(@selected_resources, resource)}
                    class="mt-1 h-4 w-4 rounded border-base-light-300 text-primary-light focus:ring-primary-light dark:border-base-dark-600 dark:bg-base-dark-800"
                  />
                </div>

                <div class="space-y-3 mb-4">
                  <div class="flex items-center justify-between text-sm">
                    <span class="text-base-light-600 dark:text-base-dark-400">Prototypes:</span>
                    <span class="font-semibold text-base-light-900 dark:text-base-dark-100">
                      <%= length(prototypes) %>
                    </span>
                  </div>
                  <div class="flex flex-wrap gap-1">
                    <%= for prototype <- Enum.take(prototypes, 3) do %>
                      <span class="px-2 py-1 text-xs rounded bg-base-light-100 dark:bg-base-dark-800 text-base-light-700 dark:text-base-dark-300">
                        <%= inspect(prototype.ref) %>
                      </span>
                    <% end %>
                    <%= if length(prototypes) > 3 do %>
                      <span class="px-2 py-1 text-xs text-base-light-500 dark:text-base-dark-400">
                        +<%= length(prototypes) - 3 %> more
                      </span>
                    <% end %>
                  </div>
                </div>

                <button
                  type="button"
                  phx-click="navigate_to_resource"
                  phx-value-resource={Atom.to_string(resource)}
                  class="w-full px-4 py-2 rounded-md text-sm font-medium bg-base-light-100 hover:bg-base-light-200 dark:bg-base-dark-800 dark:hover:bg-base-dark-700 transition-colors"
                >
                  View Prototypes →
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Empty State -->
        <div :if={Enum.empty?(@resources)} class="bg-white dark:bg-base-dark-900 rounded-lg shadow-sm p-12 text-center border border-base-light-200 dark:border-base-dark-700">
          <svg class="mx-auto h-12 w-12 text-base-light-400 dark:text-base-dark-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-base-light-900 dark:text-base-dark-100">
            No resources with prototypes
          </h3>
          <p class="mt-1 text-sm text-base-light-500 dark:text-base-dark-400">
            No resources in your application have prototypes defined with AshScenario.Dsl
          </p>
        </div>

        <!-- Results Section -->
        <div :if={@last_result} class="mt-8 bg-white dark:bg-base-dark-900 rounded-lg shadow-sm border border-base-light-200 dark:border-base-dark-700 overflow-hidden">
          <div class="p-4 border-b border-base-light-200 dark:border-base-dark-700 bg-gradient-to-r from-success-light-50 to-success-light-100 dark:from-success-dark-900/50 dark:to-success-dark-800/50">
            <div class="flex items-center justify-between">
              <h3 class="text-sm font-semibold text-base-light-900 dark:text-base-dark-100">
                Execution Results
              </h3>
              <button
                type="button"
                phx-click="toggle_result"
                class="text-sm text-base-light-600 hover:text-base-light-900 dark:text-base-dark-400 dark:hover:text-base-dark-100 transition-colors"
              >
                <%= if @show_result do %>
                  Hide Details
                <% else %>
                  Show Details
                <% end %>
              </button>
            </div>
          </div>
          <div :if={@show_result} class="p-4 max-h-96 overflow-auto">
            <pre class="text-xs font-mono text-base-light-800 dark:text-base-dark-200 whitespace-pre-wrap"><%= inspect(@last_result, pretty: true, limit: :infinity) %></pre>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp find_resources_with_prototypes do
    # Find all Ash resources with prototypes
    Application.loaded_applications()
    |> Enum.flat_map(fn {app, _, _} ->
      {:ok, modules} = :application.get_key(app, :modules)
      modules
    end)
    |> Enum.filter(&ash_resource?/1)
    |> Enum.filter(&Info.has_prototypes?/1)
    |> Enum.map(fn resource ->
      {resource, Info.prototypes(resource)}
    end)
    |> Enum.sort_by(fn {resource, _} -> inspect(resource) end)
  end

  defp ash_resource?(module) do
    Code.ensure_loaded?(module) && function_exported?(module, :spark_is, 0) &&
      module.spark_is() == Ash.Resource
  rescue
    _ -> false
  end

  defp flash_class(:info),
    do:
      "rounded-lg border border-success-light-300 bg-success-light-50 p-4 text-success-light-700 dark:border-success-dark-600 dark:bg-success-dark-900/50 dark:text-success-dark-200"

  defp flash_class(:error),
    do:
      "rounded-lg border border-danger-light-300 bg-danger-light-50 p-4 text-danger-light-700 dark:border-danger-dark-600 dark:bg-danger-dark-900/50 dark:text-danger-dark-200"

  defp flash_class(_),
    do:
      "rounded-lg border border-base-light-300 dark:border-base-dark-700 bg-base-light-50 dark:bg-base-dark-900 p-4 text-base-light-700 dark:text-base-dark-200"
end
