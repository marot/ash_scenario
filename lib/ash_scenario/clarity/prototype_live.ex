defmodule AshScenario.Clarity.PrototypeLive do
  @moduledoc false

  use Phoenix.LiveView

  alias AshScenario.Info

  @impl Phoenix.LiveView
  def mount(_params, %{"resource" => resource_string} = session, socket) do
    resource = load_resource!(resource_string)
    relationships = get_relationships(resource)
    prefix = Map.get(session, "prefix", "")

    socket =
      socket
      |> assign(
        resource: resource,
        resource_name: inspect(resource),
        prototypes: Info.prototypes(resource),
        default_create: Info.create(resource),
        running: nil,
        last_result: nil,
        show_result: false,
        relationships: relationships,
        prefix: prefix
      )

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("run", %{"prototype" => ref, "strategy" => strategy}, socket) do
    prototype = String.to_existing_atom(ref)
    strategy = parse_strategy(strategy)
    resource = socket.assigns.resource

    socket = socket |> assign(running: {prototype, strategy}) |> clear_flash()

    case AshScenario.run([{resource, prototype}], strategy: strategy) do
      {:ok, result} ->
        socket =
          socket
          |> put_flash(:info, success_message(resource, prototype, strategy, result))
          |> assign(last_result: result, running: nil, show_result: true)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, error_message(prototype, strategy, reason))
          |> assign(running: nil)

        {:noreply, socket}
    end
  end

  def handle_event("run_all", _params, socket) do
    resource = socket.assigns.resource

    socket = socket |> assign(running: :all) |> clear_flash()

    case AshScenario.run_all(resource) do
      {:ok, result} ->
        socket =
          socket
          |> put_flash(:info, "Successfully created #{map_size(result)} prototypes")
          |> assign(last_result: result, running: nil, show_result: true)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, format_error(reason))
          |> assign(running: nil)

        {:noreply, socket}
    end
  end

  def handle_event("toggle_result", _params, socket) do
    {:noreply, assign(socket, show_result: !socket.assigns.show_result)}
  end

  def handle_event("dismiss_flash", %{"key" => key}, socket) do
    {:noreply, clear_flash(socket, String.to_existing_atom(key))}
  end

  def handle_event("navigate_to_related", %{"resource" => resource_string}, socket) do
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
    <div class="min-h-screen bg-gradient-to-br from-base-light-50 to-base-light-100 dark:from-base-dark-900 dark:to-base-dark-800">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-base-light-900 dark:text-base-dark-100 mb-2">
            AshScenario Prototypes
          </h1>
          <p class="text-base-light-600 dark:text-base-dark-400">
            Generate and manage prototype data for <span class="font-mono font-semibold text-primary-light dark:text-primary-dark">{@resource_name}</span>
          </p>
        </div>

        <!-- Flash Messages -->
        <.flash_messages flash={@flash} />

        <!-- Action Bar -->
        <div class="mb-8 bg-white dark:bg-base-dark-900 rounded-lg shadow-sm p-6 border border-base-light-200 dark:border-base-dark-700">
          <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
            <div class="flex-1">
              <h2 class="text-lg font-semibold text-base-light-900 dark:text-base-dark-100 mb-1">
                Batch Operations
              </h2>
              <p class="text-sm text-base-light-600 dark:text-base-dark-400">
                Execute all prototypes at once using the default create action
              </p>
            </div>
            <button
              type="button"
              class={[
                "px-6 py-2.5 rounded-lg font-medium transition-all duration-200",
                "bg-primary-light hover:bg-primary-light/90 text-white dark:bg-primary-dark dark:hover:bg-primary-dark/90",
                "shadow-sm hover:shadow-md transform hover:-translate-y-0.5",
                "disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:transform-none disabled:hover:shadow-sm"
              ]}
              phx-click="run_all"
              disabled={@running != nil}
            >
              <%= if @running == :all do %>
                <span class="flex items-center gap-2">
                  <svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Running...
                </span>
              <% else %>
                Run All Prototypes
              <% end %>
            </button>
          </div>
        </div>

        <!-- Relationships Section -->
        <div :if={!Enum.empty?(@relationships)} class="mb-8 bg-white dark:bg-base-dark-900 rounded-lg shadow-sm p-6 border border-base-light-200 dark:border-base-dark-700">
          <h2 class="text-lg font-semibold text-base-light-900 dark:text-base-dark-100 mb-4">
            Related Resources
          </h2>
          <p class="text-sm text-base-light-600 dark:text-base-dark-400 mb-4">
            Navigate to prototype pages of related resources
          </p>
          <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <%= for {rel_name, dest_resource, has_prototypes} <- @relationships do %>
              <div class="flex items-center justify-between p-3 rounded-md border border-base-light-200 dark:border-base-dark-700 hover:bg-base-light-50 dark:hover:bg-base-dark-800 transition-colors">
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-medium text-base-light-900 dark:text-base-dark-100 truncate">
                    <%= Atom.to_string(rel_name) %>
                  </p>
                  <p class="text-xs text-base-light-500 dark:text-base-dark-400 font-mono truncate">
                    <%= inspect(dest_resource) |> String.split(".") |> List.last() %>
                  </p>
                </div>
                <%= if has_prototypes do %>
                  <button
                    type="button"
                    phx-click="navigate_to_related"
                    phx-value-resource={Atom.to_string(dest_resource)}
                    class="ml-2 px-3 py-1 text-xs font-medium rounded bg-primary-light hover:bg-primary-light/90 text-white dark:bg-primary-dark dark:hover:bg-primary-dark/90 transition-colors"
                  >
                    View Prototypes →
                  </button>
                <% else %>
                  <span class="ml-2 px-2 py-1 text-xs text-base-light-500 dark:text-base-dark-400 italic">
                    No prototypes
                  </span>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Empty State -->
        <div :if={Enum.empty?(@prototypes)} class="bg-white dark:bg-base-dark-900 rounded-lg shadow-sm p-12 text-center border border-base-light-200 dark:border-base-dark-700">
          <svg class="mx-auto h-12 w-12 text-base-light-400 dark:text-base-dark-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-base-light-900 dark:text-base-dark-100">
            No prototypes defined
          </h3>
          <p class="mt-1 text-sm text-base-light-500 dark:text-base-dark-400">
            This resource doesn't have any prototypes configured with AshScenario.Dsl
          </p>
        </div>

        <!-- Prototypes Grid -->
        <div :if={!Enum.empty?(@prototypes)} class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          <%= for prototype <- @prototypes do %>
            <div class="bg-white dark:bg-base-dark-900 rounded-lg shadow-sm hover:shadow-md transition-shadow duration-200 border border-base-light-200 dark:border-base-dark-700 overflow-hidden">
              <!-- Card Header -->
              <div class="p-6 border-b border-base-light-200 dark:border-base-dark-700 bg-gradient-to-r from-base-light-50 to-base-light-100 dark:from-base-dark-800 dark:to-base-dark-900">
                <h3 class="text-lg font-semibold text-base-light-900 dark:text-base-dark-100 mb-1">
                  <%= inspect(prototype.ref) %>
                </h3>
                <p class="text-xs text-base-light-600 dark:text-base-dark-400">
                  Action: <span class="font-mono text-primary-light dark:text-primary-dark"><%= inspect(prototype_action(prototype, @default_create)) %></span>
                </p>
              </div>

              <!-- Card Body -->
              <div class="p-6 space-y-4">
                <!-- Attributes -->
                <div :if={prototype.attributes not in [nil, []]}>
                  <h4 class="text-xs font-semibold uppercase tracking-wider text-base-light-500 dark:text-base-dark-400 mb-2">
                    Attributes
                  </h4>
                  <div class="space-y-2">
                    <%= for {name, value} <- Keyword.new(prototype.attributes) do %>
                      <div class="flex justify-between items-start gap-2">
                        <span class="text-sm font-medium text-base-light-700 dark:text-base-dark-300">
                          <%= inspect(name) %>
                        </span>
                        <span class="text-sm text-base-light-600 dark:text-base-dark-400 font-mono text-right">
                          <%= format_compact_value(value) %>
                        </span>
                      </div>
                    <% end %>
                  </div>
                </div>

                <!-- Metadata -->
                <div :if={prototype.virtuals && prototype.virtuals != MapSet.new()} class="pt-2 border-t border-base-light-200 dark:border-base-dark-800">
                  <p class="text-xs text-base-light-500 dark:text-base-dark-400">
                    <span class="font-semibold">Virtual:</span>
                    <span class="font-mono"><%= prototype.virtuals |> Enum.join(", ") %></span>
                  </p>
                </div>

                <div :if={prototype.function} class="pt-2 border-t border-base-light-200 dark:border-base-dark-800">
                  <p class="text-xs text-base-light-500 dark:text-base-dark-400">
                    <span class="font-semibold">Function:</span>
                    <span class="font-mono"><%= format_function(prototype.function) %></span>
                  </p>
                </div>
              </div>

              <!-- Card Actions -->
              <div class="p-6 pt-0 flex gap-2">
                <button
                  type="button"
                  class={[
                    "flex-1 px-4 py-2 rounded-md text-sm font-medium transition-all duration-200",
                    "bg-primary-light hover:bg-primary-light/90 text-white dark:bg-primary-dark dark:hover:bg-primary-dark/90",
                    "disabled:opacity-50 disabled:cursor-not-allowed"
                  ]}
                  phx-click="run"
                  phx-value-prototype={Atom.to_string(prototype.ref)}
                  phx-value-strategy="database"
                  disabled={@running != nil}
                >
                  <%= if @running == {prototype.ref, :database} do %>
                    <span class="flex items-center justify-center gap-2">
                      <svg class="animate-spin h-3 w-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                      Creating...
                    </span>
                  <% else %>
                    Database
                  <% end %>
                </button>
                <button
                  type="button"
                  class={[
                    "flex-1 px-4 py-2 rounded-md text-sm font-medium transition-all duration-200",
                    "bg-base-light-200 hover:bg-base-light-300 text-base-light-900 dark:bg-base-dark-700 dark:hover:bg-base-dark-600 dark:text-base-dark-100",
                    "disabled:opacity-50 disabled:cursor-not-allowed"
                  ]}
                  phx-click="run"
                  phx-value-prototype={Atom.to_string(prototype.ref)}
                  phx-value-strategy="struct"
                  disabled={@running != nil}
                >
                  <%= if @running == {prototype.ref, :struct} do %>
                    <span class="flex items-center justify-center gap-2">
                      <svg class="animate-spin h-3 w-3" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                      Creating...
                    </span>
                  <% else %>
                    Struct
                  <% end %>
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Results Section -->
        <div :if={@last_result} class="mt-8 bg-white dark:bg-base-dark-900 rounded-lg shadow-sm border border-base-light-200 dark:border-base-dark-700 overflow-hidden">
          <div class="p-4 border-b border-base-light-200 dark:border-base-dark-700 bg-gradient-to-r from-success-light-50 to-success-light-100 dark:from-success-dark-900/50 dark:to-success-dark-800/50">
            <div class="flex items-center justify-between">
              <h3 class="text-sm font-semibold text-base-light-900 dark:text-base-dark-100">
                Last Execution Result
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

  defp prototype_action(prototype, default), do: prototype.action || default.action

  defp flash_messages(assigns) do
    ~H"""
    <div :if={get_flash_messages(@flash) != []} class="mb-6 space-y-3">
      <%= for {kind, message} <- get_flash_messages(@flash) do %>
        <div class={flash_class(kind)} role="alert">
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-start gap-3">
              <.flash_icon kind={kind} />
              <p class="text-sm">
                <%= message %>
              </p>
            </div>
            <button
              type="button"
              phx-click="dismiss_flash"
              phx-value-key={Atom.to_string(kind)}
              class="text-current opacity-70 hover:opacity-100 transition-opacity"
            >
              <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp flash_icon(assigns) do
    ~H"""
    <%= case @kind do %>
      <% :info -> %>
        <svg class="h-5 w-5 text-success-light-600 dark:text-success-dark-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      <% :error -> %>
        <svg class="h-5 w-5 text-danger-light-600 dark:text-danger-dark-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      <% _ -> %>
        <svg class="h-5 w-5 text-base-light-600 dark:text-base-dark-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
    <% end %>
    """
  end

  defp get_flash_messages(flash) do
    Enum.flat_map(flash, fn
      {key, message} when is_binary(key) ->
        case safe_to_existing_atom(key) do
          {:ok, atom_key} -> [{atom_key, message}]
          :error -> []
        end

      {key, message} when is_atom(key) ->
        [{key, message}]
    end)
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

  defp format_compact_value(value) when is_binary(value) and byte_size(value) > 30,
    do: String.slice(value, 0, 30) <> "..."

  defp format_compact_value(value) when is_list(value),
    do: "[#{length(value)} items]"

  defp format_compact_value(value) when is_map(value),
    do: "%{#{map_size(value)} keys}"

  defp format_compact_value(value),
    do: inspect(value)

  defp format_function({module, function, arity}), do: inspect({module, function, arity})
  defp format_function(fun) when is_function(fun, 2), do: "#Function<.../2>"
  defp format_function(fun), do: inspect(fun)

  defp parse_strategy("struct"), do: :struct
  defp parse_strategy("database"), do: :database
  defp parse_strategy(_), do: :database

  defp success_message(resource, prototype, strategy, result) do
    case Map.get(result, {resource, prototype}) do
      nil ->
        "Created #{inspect(prototype)} using #{strategy} strategy."

      record ->
        "Created #{inspect(prototype)} using #{strategy} strategy: #{inspect(record)}"
    end
  end

  defp error_message(prototype, strategy, reason) do
    "Failed to create #{inspect(prototype)} using #{strategy} strategy: #{format_error(reason)}"
  end

  defp format_error({:error, error}) do
    if Ash.Error.ash_error?(error) do
      Ash.Error.error_descriptions(error)
    else
      error
    end
  end

  defp format_error(%{message: message}), do: message
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp load_resource!(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError ->
      reraise ArgumentError, "Unknown resource module #{string}", __STACKTRACE__
  end

  defp safe_to_existing_atom(key) do
    {:ok, String.to_existing_atom(key)}
  rescue
    ArgumentError -> :error
  end

  defp get_relationships(resource) do
    resource
    |> Ash.Resource.Info.relationships()
    |> Enum.map(fn rel ->
      dest = rel.destination
      has_prototypes = Info.has_prototypes?(dest)
      {rel.name, dest, has_prototypes}
    end)
    |> Enum.filter(fn {_, dest, _} ->
      Code.ensure_loaded?(dest) && function_exported?(dest, :spark_is, 0) &&
        dest.spark_is() == Ash.Resource
    end)
  rescue
    _ -> []
  end
end
