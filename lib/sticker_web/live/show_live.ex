defmodule StickerWeb.ShowLive do
  use StickerWeb, :live_view
  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO

  @num_results 21

  def mount(%{"id" => id}, session, socket) do
    local_user_id = session["local_user_id"]

    case Predictions.get_viewable_prediction(id, socket.assigns[:current_user], local_user_id) do
      {:ok, prediction} ->
        if connected?(socket) and is_binary(local_user_id) and local_user_id == prediction.local_user_id do
          Phoenix.PubSub.subscribe(Sticker.PubSub, "user:#{local_user_id}")
        end

        {:ok,
         socket
         |> assign(
           prediction: prediction,
           local_user_id: local_user_id,
           given_feedback: false,
           form: to_form(%{"prompt" => prediction.prompt})
         )
         |> assign_async(
           :similar_stickers,
           fn ->
             {:ok,
              %{similar_stickers: Sticker.Embeddings.search_stickers(prediction.prompt, @num_results)}}
           end
         ), temporary_assigns: [{SEO.key(), nil}]}

      {:error, :private} ->
        {:ok,
         socket
         |> put_flash(:error, "This sticker is private.")
         |> redirect(to: ~p"/")}
    end
  end

  def handle_info({event, %{id: id} = prediction}, socket)
      when event in [:prediction_loading, :prediction_completed, :prediction_failed] do
    if id == socket.assigns.prediction.id do
      {:noreply, assign(socket, prediction: prediction)}
    else
      {:noreply, socket}
    end
  end

  def handle_params(_params, _url, socket) do
    prediction = socket.assigns.prediction

    {:noreply,
     SEO.assign(
       socket,
       PageSEO.page("/sticker/#{prediction.id}",
         title: "AI Sticker: #{prediction.prompt}",
         description:
           "View and download an AI generated sticker for #{prediction.prompt}. Use it as sticker inspiration or regenerate a variation.",
         image: PageSEO.absolute_image_url(prediction.sticker_output)
       )
     )}
  end

  def handle_event("save", %{"prompt" => prompt}, socket) do
    {:noreply, socket |> push_redirect(to: ~p"/?prompt=#{prompt}")}
  end

  def handle_event("click-event", %{"event" => event}, socket) do
    {:ok, _event} = Predictions.log_event(event)
    {:noreply, socket}
  end

  def handle_event("flag", %{"id" => id}, socket) do
    prediction = Predictions.get_prediction!(id)

    {:ok, _prediction} =
      Predictions.update_prediction(prediction, %{
        flag: true
      })

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Your wish is granted. This sticker is reported."
     )}
  end

  def handle_event("thumbs-up", %{"id" => id}, socket) do
    prediction = Predictions.get_prediction!(id)

    {:ok, _prediction} =
      Predictions.update_prediction(prediction, %{
        score: prediction.score + 1,
        count_votes: prediction.count_votes + 1
      })

    {:noreply,
     socket |> assign(given_feedback: true) |> put_flash(:info, "Thanks for your rating!")}
  end

  def handle_event("thumbs-down", %{"id" => id}, socket) do
    prediction = Predictions.get_prediction!(id)

    {:ok, _prediction} =
      Predictions.update_prediction(prediction, %{
        score: prediction.score - 1,
        count_votes: prediction.count_votes + 1
      })

    {:noreply,
     socket |> assign(given_feedback: true) |> put_flash(:info, "Thanks for your rating!")}
  end

  def handle_event("toggle-favorite", %{"id" => id}, socket) do
    if socket.assigns.local_user_id == socket.assigns.prediction.local_user_id do
      {:ok, prediction} = Predictions.toggle_favorite(id, socket.assigns.local_user_id)
      {:noreply, socket |> assign(prediction: prediction)}
    else
      {:noreply, put_flash(socket, :error, "Sign in to save stickers.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    if owns_prediction?(socket) do
      {:ok, _prediction} = Predictions.delete_user_prediction(id, socket.assigns.local_user_id)
      {:noreply, socket |> put_flash(:info, "Sticker deleted.") |> push_navigate(to: ~p"/stickers")}
    else
      {:noreply, put_flash(socket, :error, "You can only delete your own stickers.")}
    end
  end

  def owns_prediction?(socket) do
    owns_prediction?(
      socket.assigns[:current_user],
      socket.assigns[:local_user_id],
      socket.assigns.prediction
    )
  end

  def owns_prediction?(current_user, prediction), do: owns_prediction?(current_user, nil, prediction)

  def owns_prediction?(%{public_id: public_id}, _local_user_id, %{local_user_id: owner_id})
      when is_binary(owner_id) and owner_id == public_id,
    do: true

  def owns_prediction?(_current_user, local_user_id, %{local_user_id: owner_id})
      when is_binary(owner_id) and owner_id == local_user_id,
      do: true

  def owns_prediction?(_user, _local_user_id, _prediction), do: false
end
