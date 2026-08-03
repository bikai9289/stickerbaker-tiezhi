defmodule StickerWeb.HomeLive do
  use StickerWeb, :live_view
  alias Sticker.GenerationLauncher
  alias Sticker.GenerationCredits
  alias Sticker.GuestGenerationGate
  alias Sticker.GuestTrials
  alias Sticker.PromptInput
  alias Sticker.Predictions
  alias Sticker.Repo
  alias Sticker.Turnstile
  alias StickerWeb.SEO, as: PageSEO

  @accepted ~w(.jpg .jpeg .png)
  @face_sticker_prompt "A cute, clean portrait sticker with a white border, expressive face, simple background, high quality"
  @gate_errors [
    :guest_identity_missing,
    :guest_credits_exhausted,
    :guest_ip_limited,
    :turnstile_required,
    :turnstile_invalid,
    :turnstile_expired,
    :turnstile_unavailable,
    :attempt_duplicate,
    :invalid_generation_request
  ]

  def mount(_params, session, socket) do
    local_user_id = session["local_user_id"]
    guest_user_id = session["guest_user_id"]
    guest_trial = guest_trial_for(socket.assigns[:current_user], local_user_id)
    recent_predictions = home_predictions(local_user_id)

    if connected?(socket) do
      resume_active_predictions(recent_predictions)
    end

    {:ok,
     socket
     |> SEO.assign(
       PageSEO.page("/",
         title: "AI Sticker Maker - Free AI Sticker Generator Online",
         description:
           "Create up to 3 custom AI stickers from text prompts or portraits without an account, then download completed designs as PNG or WebP files."
       )
     )
     |> assign(form: to_form(%{"prompt" => ""}))
     |> assign(:generator_mode, :text)
     |> assign(:batch_mode, false)
     |> assign(:prompt_restored?, false)
     |> assign(local_user_id: local_user_id)
     |> assign(guest_user_id: guest_user_id)
     |> assign(canonical_ip: session["guest_client_ip"])
     |> assign(guest_trial: guest_trial)
     |> assign(request_id: Ecto.UUID.generate())
     |> assign(turnstile_token: nil)
     |> assign(turnstile_site_key: Turnstile.site_key())
     |> assign(
       turnstile_required?: repeat_guest_challenge?(socket.assigns[:current_user], guest_trial)
     )
     |> assign(:showcase_items, showcase_items())
     |> assign(:my_eager_ids, eager_prediction_ids(recent_predictions))
     |> stream(:my_predictions, recent_predictions)
     |> allow_upload(:image,
       accept: @accepted,
       max_entries: 1,
       max_file_size: 8_000_000,
       auto_upload: false
     )}
  end

  def handle_params(params, _, socket) do
    socket =
      case params do
        %{"prompt" => prompt} ->
          socket
          |> assign(form: to_form(%{"prompt" => prompt}))
          |> assign(:prompt_restored?, true)

        _params ->
          socket
      end

    socket =
      if params["mode"] == "portrait" do
        assign(socket, :generator_mode, :portrait)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("validate", %{"prompt" => prompt}, socket) do
    {:noreply, socket |> assign(form: to_form(%{"prompt" => prompt}))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("switch-generator-mode", %{"mode" => "text"}, socket) do
    {:noreply, assign(socket, :generator_mode, :text)}
  end

  def handle_event("switch-generator-mode", %{"mode" => "portrait"}, socket) do
    {:noreply, assign(socket, :generator_mode, :portrait)}
  end

  def handle_event("toggle-batch-mode", _params, socket) do
    {:noreply, assign(socket, :batch_mode, !socket.assigns.batch_mode)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :image, ref)}
  end

  def handle_event("assign-user-id", _params, socket), do: {:noreply, socket}

  def handle_event("turnstile-token", %{"token" => token}, socket) do
    {:noreply, assign(socket, :turnstile_token, String.trim(to_string(token)))}
  end

  def handle_event("save", %{"prompt" => prompt}, socket) do
    if socket.assigns.generator_mode == :portrait do
      start_portrait_generation(socket)
    else
      start_text_generation(socket, prompt)
    end
  end

  def handle_event("cancel-generation", %{"id" => id}, socket) do
    user_id = generation_user_id(socket)

    case Predictions.cancel_user_prediction(id, user_id) do
      {:ok, prediction} ->
        {:noreply,
         socket
         |> refresh_credit_assigns(user_id)
         |> mark_prediction_eager(prediction)
         |> stream_insert(:my_predictions, prediction)
         |> push_event("generation-cancel-result", %{context: "home", outcome: "canceled"})
         |> put_flash(:info, "Generation canceled. 1 credit was returned.")}

      {:error, :not_cancelable} ->
        {:noreply,
         socket
         |> push_event("generation-cancel-result", %{context: "home", outcome: "not_cancelable"})
         |> put_flash(:error, "This generation has already finished or stopped.")}
    end
  end

  defp start_text_generation(socket, prompt) do
    user_id = generation_user_id(socket)

    with {:ok, prompts} <- PromptInput.parse(prompt, batch?: socket.assigns.batch_mode),
         {:ok, _authorization} <- authorize_generation(socket, :text, length(prompts)),
         {:ok, credit_result, predictions} <-
           start_text_predictions(socket.assigns.current_user, user_id, prompts) do
      Enum.each(predictions, &GenerationLauncher.start_text/1)

      socket =
        Enum.reduce(predictions, socket, fn prediction, acc ->
          acc
          |> mark_prediction_eager(prediction)
          |> stream_insert(:my_predictions, prediction, at: 0)
        end)

      {:noreply,
       socket
       |> assign_credit_result(credit_result)
       |> complete_generation_request()
       |> assign(form: to_form(%{"prompt" => ""}))
       |> track_guest_generation(credit_result, "text", length(predictions))
       |> put_flash(:info, generation_started_message(predictions))}
    else
      {:error, reason} when reason in @gate_errors ->
        generation_gate_error(socket, reason)

      {:error, :empty_prompt} ->
        {:noreply, put_flash(socket, :error, "Add at least one sticker prompt.")}

      {:error, :prompt_too_long} ->
        {:noreply, put_flash(socket, :error, "Each prompt must be 1,000 characters or fewer.")}

      {:error, :too_many_prompts} ->
        {:noreply, put_flash(socket, :error, "Batch mode supports up to 5 prompts at a time.")}

      {:error, :insufficient_credits} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You have used your free credits. Visit Pricing to buy more credits."
         )}

      {:error, :guest_insufficient_credits} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Your 3 free guest generations are used. Create an account to keep your stickers and buy more credits."
         )}

      {:error, :missing_guest_identity} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "We could not prepare your guest trial. Refresh the page or sign in to continue."
         )}

      {:error, :invalid_guest_identity} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "We could not prepare your guest trial. Refresh the page or sign in to continue."
         )}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, "Daily generation limit reached. Try again tomorrow.")}

      {:error, :active_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Too many stickers are already processing. Wait for a few to finish."
         )}

      {:error, :create_failed, credit_result} ->
        {:noreply,
         socket
         |> assign_credit_result(credit_result)
         |> put_flash(:error, "Could not start sticker generation. Your credit was refunded.")}

      {:error, :create_failed} ->
        {:noreply,
         put_flash(socket, :error, "Could not start sticker generation. No credit was charged.")}
    end
  end

  def handle_info({:moderation_complete, prediction}, socket) do
    if prediction.moderation_score < 9 do
      {:noreply,
       socket
       |> put_flash(:info, "AI generated safety rating:  #{10 - prediction.moderation_score}/10")
       |> mark_prediction_eager(prediction)
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
     |> mark_prediction_eager(prediction)
     |> stream_insert(:my_predictions, prediction, at: 0)}
  end

  def handle_info({:prediction_loading, prediction}, socket) do
    {:noreply,
     socket
     |> mark_prediction_eager(prediction)
     |> stream_insert(:my_predictions, prediction, at: 0)
     |> put_flash(:info, "Sticker is processing. This can take a little while.")}
  end

  def handle_info({:prediction_failed, prediction}, socket) do
    {:noreply,
     socket
     |> mark_prediction_eager(prediction)
     |> stream_insert(:my_predictions, prediction, at: 0)
     |> put_flash(
       :error,
       "Image generation failed or timed out. Try a simpler prompt or generate again."
     )}
  end

  def handle_info({:prediction_completed, prediction}, socket) do
    {:noreply,
     socket
     |> mark_prediction_eager(prediction)
     |> stream_insert(:my_predictions, prediction)
     |> put_flash(:info, "Sticker generated! Click it to download.")}
  end

  def handle_info({:moderation_failed, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  defp start_text_predictions(_current_user, _user_id, []), do: {:error, :empty_prompt}
  defp start_text_predictions(nil, nil, _prompts), do: {:error, :missing_guest_identity}

  defp start_text_predictions(current_user, user_id, prompts) do
    credit_count = length(prompts)
    batch_id = batch_id()

    with :ok <- Predictions.check_generation_limits(user_id, credit_count) do
      Repo.transaction(fn ->
        with {:ok, credit_result} <-
               GenerationCredits.spend(current_user, user_id, credit_count),
             {:ok, predictions} <-
               create_text_prediction_batch(prompts, user_id, batch_id, credit_result) do
          {credit_result, predictions}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, {credit_result, predictions}} -> {:ok, credit_result, predictions}
        {:error, :create_failed} -> {:error, :create_failed}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp create_text_prediction_batch(prompts, user_id, batch_id, credit_result) do
    Enum.reduce_while(prompts, {:ok, []}, fn prompt, {:ok, predictions} ->
      case Predictions.create_prediction(%{
             prompt: prompt,
             local_user_id: user_id,
             status: :starting,
             batch_id: batch_id,
             credit_source: credit_result.credit_source,
             credit_owner_id: credit_result.credit_owner_id
           }) do
        {:ok, prediction} -> {:cont, {:ok, [prediction | predictions]}}
        {:error, _changeset} -> {:halt, {:error, :create_failed}}
      end
    end)
    |> case do
      {:ok, predictions} -> {:ok, Enum.reverse(predictions)}
      error -> error
    end
  end

  defp generation_started_message([_prediction]), do: "Sticker generation started."

  defp generation_started_message(predictions),
    do: "#{length(predictions)} sticker generations started."

  defp batch_id do
    "batch-" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
  end

  defp generate_face_sticker_from_upload(socket, entry) do
    user_id = generation_user_id(socket)
    prompt = face_sticker_prompt(socket.assigns.form)

    with :ok <- ensure_generation_challenge(socket, :portrait, 1),
         {:ok, user_id} <- require_generation_user_id(user_id),
         :ok <- Predictions.check_generation_limits(user_id, 1),
         true <- GenerationCredits.has_credits?(socket.assigns.current_user, user_id, 1),
         %{data_uri: _data_uri} = upload <- uploaded_entry_data(socket, entry),
         :ok <- Sticker.ImageSafety.review(upload.data_uri),
         {:ok, source_image_url} <- save_source_image(upload),
         {:ok, _authorization} <- authorize_generation(socket, :portrait, 1),
         {:ok, credit_result, prediction} <-
           create_face_prediction(
             socket.assigns.current_user,
             user_id,
             prompt,
             upload,
             source_image_url
           ) do
      GenerationLauncher.start_face(prediction, upload.data_uri)

      {:noreply,
       socket
       |> assign_credit_result(credit_result)
       |> complete_generation_request()
       |> mark_prediction_eager(prediction)
       |> stream_insert(:my_predictions, prediction, at: 0)
       |> track_guest_generation(credit_result, "face", 1)
       |> put_flash(:info, "Face sticker generation started.")}
    else
      {:error, reason} when reason in @gate_errors ->
        generation_gate_error(socket, reason)

      {:error, :insufficient_credits} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You have used your free credits. Visit Pricing to buy more credits."
         )}

      false ->
        discard_uploaded_entry(socket, entry)

        {:noreply, put_flash(socket, :error, insufficient_credit_message(socket))}

      {:error, :guest_insufficient_credits} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Your 3 free guest generations are used. Create an account to keep your stickers and buy more credits."
         )}

      {:error, :missing_guest_identity} ->
        discard_uploaded_entry(socket, entry)

        {:noreply,
         put_flash(
           socket,
           :error,
           "We could not prepare your guest trial. Refresh the page or sign in to continue."
         )}

      {:error, :invalid_guest_identity} ->
        discard_uploaded_entry(socket, entry)

        {:noreply,
         put_flash(
           socket,
           :error,
           "We could not prepare your guest trial. Refresh the page or sign in to continue."
         )}

      {:error, :rate_limited} ->
        discard_uploaded_entry(socket, entry)

        {:noreply,
         put_flash(socket, :error, "Daily generation limit reached. Try again tomorrow.")}

      {:error, :active_limited} ->
        discard_uploaded_entry(socket, entry)

        {:noreply,
         put_flash(
           socket,
           :error,
           "Too many stickers are already processing. Wait for a few to finish."
         )}

      {:error, :invalid_image} ->
        {:noreply, put_flash(socket, :error, "Upload a valid JPG or PNG portrait under 8 MB.")}

      {:error, :unsafe_image} ->
        {:noreply,
         put_flash(socket, :error, "This upload cannot be used for sticker generation.")}

      {:error, :review_failed} ->
        {:noreply, put_flash(socket, :error, "Image safety review failed. Try again later.")}

      {:error, :source_image_upload_failed} ->
        {:noreply, put_flash(socket, :error, "Could not upload that portrait. Please try again.")}

      {:error, :create_failed, credit_result} ->
        {:noreply,
         socket
         |> assign_credit_result(credit_result)
         |> put_flash(:error, "Could not start sticker generation. Your credit was refunded.")}
    end
  end

  defp start_portrait_generation(socket) do
    case socket.assigns.uploads.image.entries do
      [entry] -> generate_face_sticker_from_upload(socket, entry)
      [] -> {:noreply, put_flash(socket, :error, "Choose a JPG or PNG portrait first.")}
    end
  end

  defp uploaded_entry_data(socket, entry) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      with {:ok, bytes} <- File.read(path),
           {:ok, uri} <- Sticker.ImageUpload.data_uri(bytes, entry.client_type) do
        {:ok, %{data_uri: uri, bytes: bytes, content_type: entry.client_type}}
      else
        _ -> {:ok, {:error, :invalid_image}}
      end
    end)
  end

  defp save_source_image(%{bytes: bytes, content_type: content_type}) do
    extension = if content_type == "image/png", do: "png", else: "jpg"

    file_name =
      "source-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}.#{extension}"

    {:ok, source_image_storage().save_r2_upload(file_name, bytes, content_type)}
  rescue
    _reason -> {:error, :source_image_upload_failed}
  end

  defp source_image_storage do
    Application.get_env(:sticker, :source_image_storage, Sticker.Utils)
  end

  defp create_face_prediction(current_user, user_id, prompt, upload, source_image_url) do
    with {:ok, credit_result} <- GenerationCredits.spend(current_user, user_id, 1) do
      case Predictions.create_prediction(%{
             prompt: prompt,
             local_user_id: user_id,
             status: :starting,
             credit_source: credit_result.credit_source,
             credit_owner_id: credit_result.credit_owner_id,
             model: "face-to-sticker",
             source_image_url: source_image_url,
             source_image_content_type: upload.content_type,
             batch_id: batch_id()
           }) do
        {:ok, prediction} ->
          {:ok, credit_result, prediction}

        {:error, _changeset} ->
          {:ok, refreshed} =
            GenerationCredits.refund(
              credit_result.credit_source,
              credit_result.credit_owner_id,
              1
            )

          {:error, :create_failed, refresh_credit_result(credit_result, refreshed)}
      end
    end
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

  defp guest_trial_for(nil, local_user_id) when is_binary(local_user_id) do
    case GuestTrials.get_or_create_allowance(local_user_id) do
      {:ok, guest_trial} -> guest_trial
      {:error, _reason} -> nil
    end
  end

  defp guest_trial_for(_current_user, _local_user_id), do: nil

  defp authorize_generation(socket, mode, task_count) do
    GuestGenerationGate.authorize(generation_gate_attrs(socket, mode, task_count))
  end

  defp ensure_generation_challenge(socket, mode, task_count) do
    with {:ok, preview} <-
           GuestGenerationGate.challenge_requirement(
             generation_gate_attrs(socket, mode, task_count)
           ) do
      if preview.challenge_required? and socket.assigns.turnstile_token in [nil, ""] do
        {:error, :turnstile_required}
      else
        :ok
      end
    end
  end

  defp generation_gate_attrs(socket, mode, task_count) do
    %{
      current_user: socket.assigns.current_user,
      guest_user_id: socket.assigns.guest_user_id,
      canonical_ip: socket.assigns.canonical_ip,
      request_id: socket.assigns.request_id,
      mode: mode,
      task_count: task_count,
      turnstile_token: socket.assigns.turnstile_token
    }
  end

  defp generation_gate_error(socket, :turnstile_required) do
    {:noreply,
     socket
     |> assign(:turnstile_required?, true)
     |> put_flash(:error, "Complete the security check to continue.")}
  end

  defp generation_gate_error(socket, reason)
       when reason in [:turnstile_invalid, :turnstile_expired] do
    {:noreply,
     socket
     |> reset_generation_request(keep_challenge?: true)
     |> put_flash(:error, "Security check expired. Please try again.")}
  end

  defp generation_gate_error(socket, :turnstile_unavailable) do
    {:noreply,
     socket
     |> reset_generation_request(keep_challenge?: true)
     |> put_flash(:error, "Security check is temporarily unavailable. Please try again.")}
  end

  defp generation_gate_error(socket, :guest_ip_limited) do
    {:noreply,
     socket
     |> reset_generation_request()
     |> put_flash(
       :error,
       "This network has reached its free generation limit for the last 24 hours. Sign in to continue with account credits."
     )}
  end

  defp generation_gate_error(socket, :guest_credits_exhausted) do
    {:noreply,
     socket
     |> reset_generation_request()
     |> put_flash(
       :error,
       "Your 3 free guest generations are used. Create an account to keep your stickers and buy more credits."
     )}
  end

  defp generation_gate_error(socket, :attempt_duplicate) do
    recent_predictions = home_predictions(generation_user_id(socket))

    {:noreply,
     socket
     |> reset_generation_request()
     |> assign(:my_eager_ids, eager_prediction_ids(recent_predictions))
     |> stream(:my_predictions, recent_predictions, reset: true)
     |> put_flash(:info, "This request was already received. Your latest results were refreshed.")}
  end

  defp generation_gate_error(socket, _reason) do
    {:noreply,
     socket
     |> reset_generation_request()
     |> put_flash(
       :error,
       "We could not prepare your guest trial. Refresh the page or sign in to continue."
     )}
  end

  defp complete_generation_request(socket) do
    reset_generation_request(socket,
      keep_challenge?:
        repeat_guest_challenge?(socket.assigns.current_user, socket.assigns.guest_trial)
    )
  end

  defp reset_generation_request(socket, opts \\ []) do
    keep_challenge? = Keyword.get(opts, :keep_challenge?, false)

    socket
    |> assign(request_id: Ecto.UUID.generate())
    |> assign(turnstile_token: nil)
    |> assign(turnstile_required?: keep_challenge?)
    |> push_event("turnstile-reset", %{})
  end

  defp repeat_guest_challenge?(nil, %{
         credits_spent: credits_spent,
         credits_remaining: credits_remaining
       })
       when credits_spent > 0 and credits_remaining > 0,
       do: Turnstile.configured?()

  defp repeat_guest_challenge?(_current_user, _guest_trial), do: false

  defp refresh_credit_assigns(%{assigns: %{current_user: nil}} = socket, user_id) do
    assign(socket, :guest_trial, GuestTrials.get_allowance(user_id))
  end

  defp refresh_credit_assigns(socket, _user_id) do
    assign(socket, :current_user, Sticker.Accounts.get_user(socket.assigns.current_user.id))
  end

  defp eager_prediction_ids(predictions) do
    predictions |> Enum.take(4) |> Enum.map(& &1.id)
  end

  defp home_predictions(nil), do: []
  defp home_predictions(user_id), do: Predictions.list_user_recent_predictions(user_id, 12)

  defp resume_active_predictions(predictions) do
    predictions
    |> Enum.filter(&(&1.status in [:starting, :moderation_succeeded, :processing]))
    |> Enum.each(&GenerationLauncher.resume_stale/1)
  end

  defp mark_prediction_eager(socket, prediction) do
    eager_ids =
      [prediction.id | socket.assigns.my_eager_ids]
      |> Enum.uniq()
      |> Enum.take(4)

    assign(socket, :my_eager_ids, eager_ids)
  end

  defp generation_user_id(%{assigns: %{local_user_id: local_user_id}})
       when is_binary(local_user_id),
       do: local_user_id

  defp generation_user_id(%{assigns: %{current_user: %{public_id: public_id}}})
       when is_binary(public_id),
       do: public_id

  defp generation_user_id(_socket), do: nil

  defp require_generation_user_id(user_id) when is_binary(user_id), do: {:ok, user_id}
  defp require_generation_user_id(_user_id), do: {:error, :missing_guest_identity}

  defp assign_credit_result(socket, %{current_user: current_user, guest_trial: guest_trial}) do
    socket
    |> assign(current_user: current_user)
    |> assign(guest_trial: guest_trial)
  end

  defp refresh_credit_result(%{credit_source: "guest"} = credit_result, refreshed),
    do: %{credit_result | guest_trial: refreshed}

  defp refresh_credit_result(%{credit_source: "account"} = credit_result, refreshed),
    do: %{credit_result | current_user: refreshed}

  defp insufficient_credit_message(%{assigns: %{current_user: nil}}),
    do:
      "Your 3 free guest generations are used. Create an account to keep your stickers and buy more credits."

  defp insufficient_credit_message(_socket),
    do: "You have used your free credits. Visit Pricing to buy more credits."

  def guest_trial_remaining(%{credits_remaining: credits_remaining}), do: credits_remaining
  def guest_trial_remaining(_guest_trial), do: GuestTrials.max_trial_credits()

  defp track_guest_generation(
         socket,
         %{credit_source: "guest", guest_trial: guest_trial},
         mode,
         count
       ) do
    remaining = guest_trial_remaining(guest_trial)

    socket
    |> push_event("launch-track", %{
      event: "guest_generation_started",
      context: "hero_generator",
      authState: "guest",
      generationMode: mode,
      promptCount: count,
      remainingTrialCredits: remaining
    })
    |> maybe_track_guest_exhausted(remaining)
  end

  defp track_guest_generation(socket, _credit_result, _mode, _count), do: socket

  defp maybe_track_guest_exhausted(socket, 0) do
    push_event(socket, "launch-track", %{
      event: "guest_trial_exhausted",
      context: "hero_generator",
      authState: "guest",
      remainingTrialCredits: 0
    })
  end

  defp maybe_track_guest_exhausted(socket, _remaining), do: socket

  attr :uploads, :map, required: true

  def face_upload_panel(assigns) do
    ~H"""
    <div id="upload" class="saas-portrait-uploader" phx-drop-target={@uploads.image.ref}>
      <label
        :if={@uploads.image.entries == []}
        for={@uploads.image.ref}
        class="saas-portrait-dropzone"
      >
        <span class="saas-upload-icon" aria-hidden="true">+</span>
        <span class="saas-reference-title">Choose a portrait</span>
        <span
          class="saas-reference-copy"
          data-analytics-event="face_upload_attempt"
          data-analytics-context="home_upload"
        >
          JPG or PNG, up to 8 MB
        </span>
      </label>
      <.live_file_input upload={@uploads.image} class="sr-only" />
      <%= for entry <- @uploads.image.entries do %>
        <article class="saas-portrait-preview">
          <figure class="saas-portrait-preview-frame">
            <.live_img_preview entry={entry} class="saas-upload-preview-img" />
          </figure>

          <div class="saas-portrait-file-meta">
            <strong><%= entry.client_name %></strong> <span>Ready to turn into a sticker</span>
            <button
              type="button"
              class="saas-upload-remove"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
            >
              Remove
            </button>
          </div>

          <%= for err <- upload_errors(@uploads.image, entry) do %>
            <p class="saas-upload-error"><%= error_to_string(err) %></p>
          <% end %>
        </article>
      <% end %>

      <%= for err <- upload_errors(@uploads.image) do %>
        <p class="saas-upload-error"><%= error_to_string(err) %></p>
      <% end %>
    </div>
    """
  end

  defp showcase_fallbacks do
    [
      %{
        image: "/images/showcase/red-haired-avatar.png",
        alt: "Red-haired character avatar sticker example",
        label: "Red-Haired Avatar",
        tag: "Avatar"
      },
      %{
        image: "/images/showcase/cute-girl-cats.png",
        alt: "Cute girl with cats sticker example",
        label: "Cute Girl & Cats",
        tag: "People"
      },
      %{
        image: "/images/showcase/stylish-couple.png",
        alt: "Stylish couple sticker example",
        label: "Stylish Couple",
        tag: "Couple"
      },
      %{
        image: "/images/showcase/hanfu-portrait.png",
        alt: "Traditional outfit portrait sticker example",
        label: "Hanfu Portrait",
        tag: "Avatar"
      },
      %{
        image: "/images/showcase/anime-boy-avatar.png",
        alt: "Anime boy avatar sticker example",
        label: "Anime Boy",
        tag: "Avatar"
      },
      %{
        image: "/images/showcase/bearded-character.png",
        alt: "Bearded character portrait sticker example",
        label: "Bearded Character",
        tag: "People"
      },
      %{
        image: "/images/showcase/banana-cat.png",
        alt: "Cute cat holding a banana sticker example",
        label: "Banana Cat",
        tag: "Animal"
      },
      %{
        image: "/images/showcase/calico-cat.png",
        alt: "Calico cat portrait sticker example",
        label: "Calico Cat",
        tag: "Animal"
      }
    ]
  end

  defp showcase_items do
    Enum.map(showcase_fallbacks(), fn item ->
      item
      |> Map.put(:type, :fallback)
      |> Map.put(:webp, webp_variant(item.image))
    end)
  end

  defp webp_variant("/images/showcase/" <> _ = path) do
    String.replace_suffix(path, ".png", ".webp")
  end

  defp webp_variant(_path), do: nil

  attr :src, :string, required: true
  attr :webp, :string, default: nil
  attr :alt, :string, required: true
  attr :class, :string, default: nil
  attr :loading, :string, default: "lazy"

  defp showcase_image(assigns) do
    ~H"""
    <picture>
      <source :if={@webp} srcset={@webp} type="image/webp" />
      <img
        src={@src}
        alt={@alt}
        class={@class}
        width="448"
        height="448"
        loading={@loading}
        decoding="async"
      />
    </picture>
    """
  end
end
