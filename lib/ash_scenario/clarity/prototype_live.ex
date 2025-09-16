if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshScenario.Clarity.PrototypeLive do
    @moduledoc false

    use Phoenix.LiveView

    alias AshScenario.Info

    @impl Phoenix.LiveView
    def mount(_params, %{"resource" => resource_string}, socket) do
      resource = load_resource!(resource_string)
      {preview_data, preview_error} = load_previews(resource)

      socket =
        socket
        |> assign(
          resource: resource,
          resource_name: inspect(resource),
          prototypes: Info.prototypes(resource),
          default_create: Info.create(resource),
          running: nil,
          last_result: nil,
          preview_data: preview_data,
          preview_error: preview_error
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
            |> assign(last_result: result, running: nil)

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
            |> put_flash(:info, "Created #{map_size(result)} prototypes for #{inspect(resource)}")
            |> assign(last_result: result, running: nil)

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> put_flash(:error, format_error(reason))
            |> assign(running: nil)

          {:noreply, socket}
      end
    end

    @impl Phoenix.LiveView
    def render(assigns) do
      ~H"""
      <div class="space-y-6 p-6">
        <div>
          <h2 class="text-xl font-semibold">AshScenario Prototypes</h2>
          <p class="text-sm text-base-light-600 dark:text-base-dark-300">
            Create prototype data for {@resource_name} directly from Clarity.
          </p>
        </div>

        <div :if={flash_messages(@flash) != []} class="space-y-3">
          <%= for {kind, message} <- flash_messages(@flash) do %>
            <div class={flash_class(kind)} role="alert">
              <%= message %>
            </div>
          <% end %>
        </div>

        <div :if={@preview_error} class="rounded border border-danger-light-200 bg-danger-light-50 px-3 py-2 text-xs text-danger-light-700 dark:border-danger-dark-600 dark:bg-danger-dark-900 dark:text-danger-dark-200">
          Failed to load preview data: {@preview_error}
        </div>

        <div class="flex items-center gap-3">
          <button
            type="button"
            class="rounded border border-base-light-400 dark:border-base-dark-600 px-3 py-1 text-xs font-semibold disabled:opacity-50"
            phx-click="run_all"
            disabled={@running != nil}
          >
            Run all prototypes (database)
          </button>
          <p class="text-xs text-base-light-500 dark:text-base-dark-400">
            Executes every prototype defined on this resource using the default action.
          </p>
        </div>

        <div :if={Enum.empty?(@prototypes)} class="rounded border border-dashed border-base-light-300 dark:border-base-dark-700 p-6 text-sm text-base-light-600 dark:text-base-dark-400">
          This resource does not define any prototypes with `AshScenario.Dsl`.
        </div>

        <div :for={prototype <- @prototypes} class="rounded border border-base-light-300 dark:border-base-dark-700">
          <div class="flex flex-col gap-4 p-4">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <div>
                <h3 class="font-medium text-base-light-900 dark:text-base-dark-100">
                  <%= inspect(prototype.ref) %>
                </h3>
                <p class="text-xs text-base-light-500 dark:text-base-dark-400">
                  Uses action <%= inspect(prototype_action(prototype, @default_create)) %>
                </p>
              </div>
              <div class="flex flex-wrap gap-2">
                <button
                  type="button"
                  class="rounded bg-primary-light text-white dark:bg-primary-dark px-3 py-1 text-xs font-semibold disabled:opacity-50"
                  phx-click="run"
                  phx-value-prototype={Atom.to_string(prototype.ref)}
                  phx-value-strategy="database"
                  disabled={@running != nil}
                >
                  Create (database)
                </button>
                <button
                  type="button"
                  class="rounded bg-base-light-900 text-white dark:bg-base-dark-100 dark:text-base-dark-900 px-3 py-1 text-xs font-semibold disabled:opacity-50"
                  phx-click="run"
                  phx-value-prototype={Atom.to_string(prototype.ref)}
                  phx-value-strategy="struct"
                  disabled={@running != nil}
                >
                  Create (struct)
                </button>
              </div>
            </div>

            <div :if={prototype.attributes not in [nil, []]} class="text-sm">
              <h4 class="font-medium text-base-light-700 dark:text-base-dark-200">Attributes</h4>
              <dl class="mt-2 grid gap-2 text-xs">
                <div :for={{name, value} <- Keyword.new(prototype.attributes)} class="grid grid-cols-[auto,1fr] gap-3">
                  <dt class="font-semibold text-base-light-700 dark:text-base-dark-200">
                    <%= inspect(name) %>
                  </dt>
                  <dd class="text-base-light-600 dark:text-base-dark-300">
                    <%= format_value(value) %>
                  </dd>
                </div>
              </dl>
            </div>

            <div :if={prototype.virtuals && prototype.virtuals != MapSet.new()} class="text-xs text-base-light-500 dark:text-base-dark-400">
              <span class="font-medium">Virtual attributes:</span>
              <%= prototype.virtuals |> Enum.join(", ") %>
            </div>

            <div :if={prototype.function} class="text-xs text-base-light-500 dark:text-base-dark-400">
              <span class="font-medium">Custom function:</span>
              <%= format_function(prototype.function) %>
            </div>

            <div :if={sample = Map.get(@preview_data, {@resource, prototype.ref})} class="text-xs">
              <h4 class="mb-1 font-medium text-base-light-700 dark:text-base-dark-200">Sample data</h4>
              <pre class="whitespace-pre-wrap break-all rounded bg-base-light-100 dark:bg-base-dark-800 p-3">
      <%= inspect(sample, pretty: true, limit: :infinity) %>
      </pre>
            </div>
          </div>
        </div>

        <div :if={@last_result} class="rounded border border-base-light-300 dark:border-base-dark-700 bg-base-light-50 dark:bg-base-dark-900 p-4 text-xs">
          <h4 class="mb-2 font-semibold text-base-light-700 dark:text-base-dark-200">Most recent result</h4>
          <pre class="whitespace-pre-wrap break-all"><%= inspect(@last_result, pretty: true, limit: :infinity) %></pre>
        </div>
      </div>
      """
    end

    defp prototype_action(prototype, default), do: prototype.action || default.action

    defp flash_messages(flash) do
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
        "rounded border border-success-light-300 bg-success-light-50 px-3 py-2 text-xs text-success-light-700 dark:border-success-dark-600 dark:bg-success-dark-900 dark:text-success-dark-200"

    defp flash_class(:error),
      do:
        "rounded border border-danger-light-300 bg-danger-light-50 px-3 py-2 text-xs text-danger-light-700 dark:border-danger-dark-600 dark:bg-danger-dark-900 dark:text-danger-dark-200"

    defp flash_class(_),
      do:
        "rounded border border-base-light-300 dark:border-base-dark-700 bg-base-light-50 dark:bg-base-dark-900 px-3 py-2 text-xs"

    defp format_value(value) when is_atom(value), do: inspect(value)

    defp format_value(value) when is_map(value),
      do: inspect(value, pretty: true, limit: :infinity)

    defp format_value(value) when is_list(value),
      do: inspect(value, pretty: true, limit: :infinity)

    defp format_value(value), do: inspect(value)

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

    defp format_error(%Ash.Error{} = error) do
      Ash.Error.to_iodata(error) |> IO.iodata_to_binary()
    end

    defp format_error(%{message: message}), do: message
    defp format_error(reason) when is_binary(reason), do: reason
    defp format_error(reason), do: inspect(reason)

    defp load_resource!(string) do
      String.to_existing_atom(string)
    rescue
      ArgumentError ->
        raise ArgumentError, "Unknown resource module #{string}"
    end

    defp load_previews(resource) do
      case Info.has_prototypes?(resource) do
        false ->
          {%{}, nil}

        true ->
          case AshScenario.run_all(resource, strategy: :struct) do
            {:ok, result} -> {result, nil}
            {:error, reason} -> {%{}, format_error(reason)}
          end
      end
    rescue
      error -> {%{}, format_error(error)}
    end

    defp safe_to_existing_atom(key) do
      {:ok, String.to_existing_atom(key)}
    rescue
      ArgumentError -> :error
    end
  end
end
