defmodule StickerWeb.HistoryLive do
  use StickerWeb, :live_view
  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO

  def mount(_params, session, socket) do
    local_user_id = session["local_user_id"]
    filters = %{status: "all", query: ""}
    predictions = if local_user_id, do: Predictions.list_user_predictions(local_user_id, filters), else: []

    {:ok,
     socket
     |> SEO.assign(
       PageSEO.noindex("/stickers",
         title: "Sticker History",
         description: "View and manage your generated AI sticker history, saved stickers, and downloads."
       )
     )
     |> assign(local_user_id: local_user_id)
     |> assign(filters: filters)
     |> assign(selected_ids: MapSet.new())
     |> assign(results: [])
     |> stream(:predictions, predictions)}
  end

  def handle_event("assign-user-id", %{"userId" => user_id}, socket) do
    {:noreply,
     socket
     |> assign(local_user_id: user_id)
     |> stream(:predictions, Predictions.list_user_predictions(user_id, socket.assigns.filters), reset: true)}
  end

  def handle_event("filter", params, socket) do
    filters = %{
      status: Map.get(params, "status", socket.assigns.filters.status),
      query: Map.get(params, "query", socket.assigns.filters.query)
    }

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(selected_ids: MapSet.new())
     |> stream(:predictions, Predictions.list_user_predictions(socket.assigns.local_user_id, filters), reset: true)}
  end

  def handle_event("toggle-select", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected_ids = socket.assigns.selected_ids

    selected_ids =
      if MapSet.member?(selected_ids, id),
        do: MapSet.delete(selected_ids, id),
        else: MapSet.put(selected_ids, id)

    {:noreply, assign(socket, selected_ids: selected_ids)}
  end

  def handle_event("clear-selection", _params, socket) do
    {:noreply, assign(socket, selected_ids: MapSet.new())}
  end

  def handle_event("delete-selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)
    {count, _} = Predictions.delete_user_predictions(ids, socket.assigns.local_user_id)

    {:noreply,
     socket
     |> assign(selected_ids: MapSet.new())
     |> stream(:predictions, Predictions.list_user_predictions(socket.assigns.local_user_id, socket.assigns.filters), reset: true)
     |> put_flash(:info, "#{count} stickers deleted.")}
  end

  def handle_event("toggle-favorite", %{"id" => id}, socket) do
    {:ok, prediction} = Predictions.toggle_favorite(id, socket.assigns.local_user_id)
    {:noreply, stream_insert(socket, :predictions, prediction)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, prediction} = Predictions.delete_user_prediction(id, socket.assigns.local_user_id)

    {:noreply,
     socket
     |> stream_delete(:predictions, prediction)
     |> put_flash(:info, "Sticker deleted.")}
  end

  def selected?(selected_ids, id), do: MapSet.member?(selected_ids, id)
end
