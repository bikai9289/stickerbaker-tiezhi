defmodule StickerWeb.HomeLive do
  use StickerWeb, :live_view
  alias Phoenix.PubSub
  alias Sticker.Accounts
  alias Sticker.Predictions

  @accepted ~w(.jpg .jpeg .png)
  @face_sticker_prompt "A cute, clean portrait sticker with a white border, expressive face, simple background, high quality"

  def mount(_params, session, socket) do
    page = 0
    per_page = 20
    max_pages = Predictions.number_moderated_predictions() / per_page

    loading_predictions =
      Predictions.list_loading_predictions(session["local_user_id"])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sticker.PubSub, "safe-prediction-firehose")
    end

    {:ok,
     socket
     |> assign(form: to_form(%{"prompt" => ""}))
     |> assign(local_user_id: session["local_user_id"])
     |> assign(page: page)
     |> assign(per_page: per_page)
     |> assign(max_pages: max_pages)
     |> stream(:my_predictions, loading_predictions)
     |> stream(:latest_predictions, Predictions.list_latest_safe_predictions(page, per_page))
     |> allow_upload(:image,
       accept: @accepted,
       max_entries: 1,
       auto_upload: true,
       progress: &handle_image_progress/3
     )}
  end

  def handle_params(%{"prompt" => prompt}, _, socket) do
    {:noreply, socket |> assign(form: to_form(%{"prompt" => prompt}))}
  end

  def handle_params(_params, _, socket) do
    {:noreply, socket}
  end

  def handle_event("load-more", _, %{assigns: assigns} = socket) do
    next_page = assigns.page + 1

    latest_predictions =
      Predictions.list_latest_safe_predictions(assigns.page, socket.assigns.per_page)

    {:noreply,
     socket
     |> assign(page: next_page)
     |> stream(:latest_predictions, latest_predictions)}
  end

  def handle_event("validate", %{"prompt" => prompt}, socket) do
    {:noreply, socket |> assign(form: to_form(%{"prompt" => prompt}))}
  end

  def handle_event("assign-user-id", %{"userId" => user_id}, socket) do
    PubSub.subscribe(Sticker.PubSub, "user:#{user_id}")

    {:noreply, socket |> assign(local_user_id: user_id)}
  end

  def handle_event("save", %{"prompt" => _prompt}, %{assigns: %{current_user: nil}} = socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Please sign in to use your 3 free sticker credits.")}
  end

  def handle_event("save", %{"prompt" => prompt}, socket) do
    user_id = socket.assigns.local_user_id

    with {:ok, current_user} <- Accounts.spend_credit(socket.assigns.current_user),
         {:ok, prediction} <-
           Predictions.create_prediction(%{
             prompt: prompt,
             local_user_id: user_id
           }) do
      send(self(), {:kick_off_sticker, prediction})

      {
        :noreply,
        socket
        |> assign(current_user: current_user)
        |> assign(form: to_form(%{"prompt" => ""}))
        |> stream_insert(:my_predictions, prediction, at: 0)
      }
    else
      {:error, :insufficient_credits} ->
        {:noreply,
         socket
         |> put_flash(:error, "You have used your free credits. Visit Pricing to buy more credits.")}

      {:error, _changeset} ->
        current_user = Accounts.refund_credit(socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(current_user: current_user)
         |> put_flash(:error, "Could not start sticker generation. Your credit was refunded.")}
    end
  end

  def handle_info({:new_prediction, prediction}, socket) do
    {:noreply, socket |> stream_insert(:latest_predictions, prediction, at: 0)}
  end

  def handle_info({:kick_off_sticker, prediction}, socket) do
    Predictions.moderate(prediction.prompt, prediction.local_user_id, prediction.id)
    {:noreply, socket}
  end

  def handle_info({:kick_off_face_to_sticker, prediction, image_uri}, socket) do
    Predictions.gen_face_to_sticker(
      prediction.prompt,
      image_uri,
      prediction.local_user_id,
      prediction.id
    )

    {:noreply, socket}
  end

  def handle_info({:moderation_complete, prediction}, socket) do
    if prediction.moderation_score < 9 do
      {:noreply,
       socket
       |> put_flash(:info, "AI generated safety rating:  #{10 - prediction.moderation_score}/10")
       |> stream_insert(:my_predictions, prediction)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "AI generated safety rating:  #{10 - prediction.moderation_score}/10")}
    end
  end

  def handle_info({:prediction_started, prediction}, socket) do
    {:noreply,
     socket
     |> stream_insert(:my_predictions, prediction, at: 0)}
  end

  def handle_info({:prediction_loading, prediction}, socket) do
    {:noreply,
     socket
     |> stream_insert(:my_predictions, prediction, at: 0)}
  end

  def handle_info({:prediction_failed, _prediction}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Uh oh, image generation failed. Likely NSFW input. Try again!")}
  end

  def handle_info({:prediction_completed, prediction}, socket) do
    {:noreply,
     socket
     |> stream_insert(:my_predictions, prediction)
     |> put_flash(:info, "Sticker generated! Click it to download.")}
  end

  defp handle_image_progress(:image, entry, socket) do
    if entry.done? do
      generate_face_sticker_from_upload(socket, entry)
    else
      {:noreply, socket}
    end
  end

  defp generate_face_sticker_from_upload(%{assigns: %{current_user: nil}} = socket, entry) do
    discard_uploaded_entry(socket, entry)

    {:noreply,
     put_flash(socket, :error, "Please sign in to use your 3 free sticker credits.")}
  end

  defp generate_face_sticker_from_upload(socket, entry) do
    user_id = socket.assigns.local_user_id || socket.assigns.current_user.public_id
    prompt = face_sticker_prompt(socket.assigns.form)

    with {:ok, current_user} <- Accounts.spend_credit(socket.assigns.current_user),
         {:ok, prediction} <-
           Predictions.create_prediction(%{
             prompt: prompt,
             local_user_id: user_id,
             model: "face-to-sticker"
           }) do
      image_uri = uploaded_entry_data_uri(socket, entry)
      send(self(), {:kick_off_face_to_sticker, prediction, image_uri})

      {:noreply,
       socket
       |> assign(current_user: current_user)
       |> stream_insert(:my_predictions, prediction, at: 0)
       |> put_flash(:info, "Face sticker generation started.")}
    else
      {:error, :insufficient_credits} ->
        discard_uploaded_entry(socket, entry)

        {:noreply,
         put_flash(socket, :error, "You have used your free credits. Visit Pricing to buy more credits.")}

      {:error, _changeset} ->
        current_user = Accounts.refund_credit(socket.assigns.current_user)
        discard_uploaded_entry(socket, entry)

        {:noreply,
         socket
         |> assign(current_user: current_user)
         |> put_flash(:error, "Could not start sticker generation. Your credit was refunded.")}
    end
  end

  defp uploaded_entry_data_uri(socket, entry) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      uri =
        path
        |> File.read!()
        |> Base.encode64()
        |> Sticker.Utils.base64_to_data_uri(entry.client_type)

      {:ok, uri}
    end)
  end

  defp discard_uploaded_entry(socket, entry) do
    consume_uploaded_entry(socket, entry, fn _meta -> {:ok, :discarded} end)
  end

  defp face_sticker_prompt(form) do
    prompt =
      form[:prompt].value
      |> to_string()
      |> String.trim()

    if prompt == "", do: @face_sticker_prompt, else: prompt
  end

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:not_accepted), do: "Sorry, we only accept #{@accepted}"
end
