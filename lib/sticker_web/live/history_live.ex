defmodule StickerWeb.HistoryLive do
  use StickerWeb, :live_view
  alias Sticker.Predictions

  def mount(_params, session, socket) do
    local_user_id = session["local_user_id"]
    predictions = if local_user_id, do: Predictions.list_user_predictions(local_user_id), else: []

    {:ok,
     socket
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
end
