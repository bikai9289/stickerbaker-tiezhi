defmodule StickerWeb.AccountLive do
  use StickerWeb, :live_view

  alias Sticker.Payments
  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO

  def mount(_params, _session, %{assigns: %{current_user: nil}} = socket) do
    {:ok,
     socket
     |> SEO.assign(
       PageSEO.noindex("/account",
         title: "AI Sticker Maker Account",
         description: "Manage AI Sticker Maker credits, saved stickers, generation history, and billing records."
       )
     )
     |> put_flash(:error, "Please sign in to view your account.")
     |> push_navigate(to: ~p"/users/log-in")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    user_id = user.public_id

    {:ok,
     socket
     |> SEO.assign(
       PageSEO.noindex("/account",
         title: "AI Sticker Maker Account",
         description: "Manage AI Sticker Maker credits, saved stickers, generation history, and billing records."
       )
     )
     |> assign(:counts, Predictions.user_prediction_counts(user_id))
     |> assign(:payments, Payments.list_user_payment_events(user.id))
     |> stream(:recent_predictions, Predictions.list_user_recent_predictions(user_id, 12))
     |> stream(:favorite_predictions, Predictions.list_user_favorite_predictions(user_id))}
  end

  def handle_event("toggle-favorite", %{"id" => id}, socket) do
    {:ok, prediction} = Predictions.toggle_favorite(id, socket.assigns.current_user.public_id)

    {:noreply,
     socket
     |> assign(:counts, Predictions.user_prediction_counts(socket.assigns.current_user.public_id))
     |> stream_insert(:recent_predictions, prediction)
     |> stream(:favorite_predictions, Predictions.list_user_favorite_predictions(socket.assigns.current_user.public_id), reset: true)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, prediction} = Predictions.delete_user_prediction(id, socket.assigns.current_user.public_id)

    {:noreply,
     socket
     |> assign(:counts, Predictions.user_prediction_counts(socket.assigns.current_user.public_id))
     |> stream_delete(:recent_predictions, prediction)
     |> stream_delete(:favorite_predictions, prediction)
     |> put_flash(:info, "Sticker deleted.")}
  end
end
