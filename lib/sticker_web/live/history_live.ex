defmodule StickerWeb.HistoryLive do
  use StickerWeb, :live_view
  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO

  def mount(_params, session, socket) do
    local_user_id = session["local_user_id"]
    predictions = if local_user_id, do: Predictions.list_user_predictions(local_user_id), else: []

    {:ok,
     socket
     |> SEO.assign(
       PageSEO.noindex("/stickers",
         title: "Sticker History",
         description: "View and manage your generated AI sticker history, saved stickers, and downloads."
       )
     )
     |> assign(local_user_id: local_user_id)
     |> assign(results: [])
     |> stream(:predictions, predictions)}
  end

  def handle_event("assign-user-id", %{"userId" => user_id}, socket) do
    {:noreply,
     socket
     |> assign(local_user_id: user_id)
     |> stream(:predictions, Predictions.list_user_predictions(user_id), reset: true)}
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
end
