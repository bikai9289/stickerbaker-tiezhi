defmodule StickerWeb.HomeLive do
  use StickerWeb, :live_view
  alias Phoenix.PubSub
  alias Sticker.Accounts
  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO

  @accepted ~w(.jpg .jpeg .png)
  @face_sticker_prompt "A cute, clean portrait sticker with a white border, expressive face, simple background, high quality"
  @max_batch_prompts 5
  @daily_generation_limit 80

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
     |> SEO.assign(
       PageSEO.page("/",
         title: "AI Sticker Maker - Free AI Sticker Generator Online",
         description:
           "Create custom AI stickers from text prompts or portraits. Start with 3 free credits and download sticker-ready designs online."
       )
     )
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
       max_file_size: 8_000_000,
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
    prompts = batch_prompts(prompt)

    case start_text_predictions(socket.assigns.current_user, user_id, prompts) do
      {:ok, current_user, predictions} ->
        Enum.each(predictions, &send(self(), {:kick_off_sticker, &1}))

        socket =
          Enum.reduce(predictions, socket, fn prediction, acc ->
            stream_insert(acc, :my_predictions, prediction, at: 0)
          end)

        {:noreply,
         socket
         |> assign(current_user: current_user)
         |> assign(form: to_form(%{"prompt" => ""}))
         |> put_flash(:info, generation_started_message(predictions))}

      {:error, :empty_prompt} ->
        {:noreply, put_flash(socket, :error, "Add at least one sticker prompt.")}

      {:error, :insufficient_credits} ->
        {:noreply,
         put_flash(socket, :error, "You have used your free credits. Visit Pricing to buy more credits.")}

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "Daily generation limit reached. Try again tomorrow.")}

      {:error, :create_failed, current_user} ->
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
     |> stream_insert(:my_predictions, prediction, at: 0)
     |> put_flash(:info, "Sticker is processing. This can take a little while.")}
  end

  def handle_info({:prediction_failed, _prediction}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Image generation failed or timed out. Try a simpler prompt or generate again.")}
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

  defp batch_prompts(prompt) do
    prompt
    |> String.split(["\n", "\r"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(@max_batch_prompts)
  end

  defp start_text_predictions(_current_user, _user_id, []), do: {:error, :empty_prompt}

  defp start_text_predictions(current_user, user_id, prompts) do
    credit_count = length(prompts)
    batch_id = batch_id()

    with :ok <- check_daily_limit(user_id, credit_count),
         {:ok, current_user} <- Accounts.spend_credits(current_user, credit_count) do
      Enum.reduce_while(prompts, {:ok, []}, fn prompt, {:ok, predictions} ->
        case Predictions.create_prediction(%{
               prompt: prompt,
               local_user_id: user_id,
               status: :starting,
               batch_id: batch_id
             }) do
          {:ok, prediction} ->
            {:cont, {:ok, [prediction | predictions]}}

          {:error, _changeset} ->
            current_user = Accounts.refund_credits(current_user, credit_count)
            {:halt, {:error, :create_failed, current_user}}
        end
      end)
      |> case do
        {:ok, predictions} -> {:ok, current_user, Enum.reverse(predictions)}
        error -> error
      end
    end
  end

  defp generation_started_message([_prediction]), do: "Sticker generation started."
  defp generation_started_message(predictions), do: "#{length(predictions)} sticker generations started."

  defp batch_id do
    "batch-" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
  end

  defp generate_face_sticker_from_upload(%{assigns: %{current_user: nil}} = socket, entry) do
    discard_uploaded_entry(socket, entry)

    {:noreply,
     put_flash(socket, :error, "Please sign in to use your 3 free sticker credits.")}
  end

  defp generate_face_sticker_from_upload(socket, entry) do
    user_id = socket.assigns.local_user_id || socket.assigns.current_user.public_id
    prompt = face_sticker_prompt(socket.assigns.form)

    with :ok <- check_daily_limit(user_id, 1),
         {:ok, current_user} <- Accounts.spend_credit(socket.assigns.current_user),
         {:ok, prediction} <-
             Predictions.create_prediction(%{
               prompt: prompt,
               local_user_id: user_id,
               model: "face-to-sticker",
               batch_id: batch_id()
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

      {:error, :rate_limited} ->
        discard_uploaded_entry(socket, entry)

        {:noreply, put_flash(socket, :error, "Daily generation limit reached. Try again tomorrow.")}

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

  defp check_daily_limit(user_id, amount) when is_binary(user_id) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    if Predictions.count_user_predictions_since(user_id, since) + amount <= @daily_generation_limit do
      :ok
    else
      {:error, :rate_limited}
    end
  end

  defp check_daily_limit(_user_id, _amount), do: {:error, :rate_limited}
end
