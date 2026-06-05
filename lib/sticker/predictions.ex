defmodule Sticker.Predictions do
  @moduledoc """
  The Predictions context.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Sticker.Accounts
  alias Sticker.Repo

  alias Sticker.Predictions.Prediction
  alias Sticker.Predictions.Event
  require Logger

  @doc """
  Moderates a prediction.
  The logic in replicate_webhook_controller.ex handles
  the webhook. Once the moderation is complete, the webhook controller automatically
  called gen_image.
  """
  def moderate(prompt, user_id, prediction_id) do
    "fofr/prompt-classifier"
    |> Replicate.Models.get!()
    |> Replicate.Models.get_latest_version!()
    |> Replicate.Predictions.create(
      %{
        prompt: "[PROMPT] #{prompt} [/PROMPT] [SAFETY_RANKING]",
        max_new_tokens: 128,
        temperature: 0.2,
        top_p: 0.9,
        top_k: 50,
        stop_sequences: "[/SAFETY_RANKING]"
      },
      "#{Sticker.Utils.get_host()}/webhooks/replicate?user_id=#{user_id}&prediction_id=#{prediction_id}"
    )
  end

  def gen_image(prompt, user_id, prediction_id) do
    case image_provider() do
      "openai" -> gen_openai_image(prompt, user_id, prediction_id)
      _provider -> gen_replicate_image(prompt, user_id, prediction_id)
    end
  end

  defp gen_replicate_image(prompt, user_id, prediction_id) do
    "fofr/sticker-maker"
    |> Replicate.Models.get!()
    |> Replicate.Models.get_version!(
      "4acb778eb059772225ec213948f0660867b2e03f277448f18cf1800b96a65a1a"
    )
    |> Replicate.Predictions.create(
      %{
        prompt: prompt,
        output_format: "webp",
        steps: 17,
        output_quality: 100,
        negative_prompt: "racist, xenophobic, antisemitic, islamophobic, bigoted"
      },
      "#{Sticker.Utils.get_host()}/webhooks/replicate?user_id=#{user_id}&prediction_id=#{prediction_id}"
    )
  end

  defp gen_openai_image(prompt, user_id, prediction_id) do
    Task.start(fn -> do_gen_openai_image(prompt, user_id, prediction_id) end)
  end

  defp do_gen_openai_image(prompt, user_id, prediction_id) do
    prediction = get_prediction!(prediction_id)

    {:ok, prediction} =
      update_prediction(prediction, %{
        status: :processing,
        model: System.get_env("OPENAI_IMAGE_MODEL", "gpt-image-2")
      })

    broadcast(user_id, {:prediction_loading, prediction})

    case Sticker.OpenAIImage.generate(prompt) do
      {:ok, base64} ->
        complete_openai_image(prediction, user_id, prediction_id, base64)

      {:error, reason} ->
        fail_openai_image(prediction, user_id, reason)
        {:error, reason}
    end
  end

  defp complete_openai_image(prediction, user_id, prediction_id, base64) do
    file_name = "prediction-#{prediction_id}-sticker.png"
    content_type = Sticker.Utils.content_type_for(file_name)
    r2_url = Sticker.Utils.save_r2_base64(file_name, base64, content_type)

    {:ok, prediction} =
      update_prediction(prediction, %{
        sticker_output: r2_url,
        output_format: Sticker.Utils.output_format(file_name),
        output_content_type: content_type,
        status: :succeeded
      })

    broadcast(user_id, {:prediction_completed, prediction})
    {:ok, prediction}
  rescue
    reason ->
      fail_openai_image(prediction, user_id, reason)
      {:error, reason}
  end

  defp fail_openai_image(prediction, user_id, reason) do
    Logger.error("OpenAI image generation failed: #{inspect(reason)}")

    {:ok, prediction} = fail_prediction_and_refund(prediction)

    broadcast(user_id, {:prediction_failed, prediction})
  end

  def gen_face_to_sticker(prompt, image_uri, user_id, prediction_id) do
    "fofr/face-to-sticker"
    |> Replicate.Models.get!()
    |> Replicate.Models.get_latest_version!()
    |> Replicate.Predictions.create(
      %{
        image: image_uri,
        steps: 20,
        width: 768,
        height: 768,
        prompt: prompt,
        upscale: false,
        upscale_steps: 10,
        negative_prompt: "racist, xenophobic, antisemitic, islamophobic, bigoted",
        prompt_strength: 4.5,
        ip_adapter_noise: 0.5,
        ip_adapter_weight: 0.2,
        instant_id_strength: 0.7
      },
      "#{Sticker.Utils.get_host()}/webhooks/replicate?user_id=#{user_id}&prediction_id=#{prediction_id}"
    )
  end

  def list_loading_predictions(nil), do: []

  def list_loading_predictions(user_id) do
    from(p in Prediction,
      where:
        p.local_user_id == ^user_id and
          p.status not in [:succeeded, :failed, :canceled],
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  def log_event(event_name) do
    %Event{event_name: event_name}
    |> Repo.insert()
  end

  defp safe_prediction_query() do
    from(p in Prediction,
      where: not is_nil(p.sticker_output) and p.is_featured == true,
      order_by: [desc: p.updated_at]
    )
  end

  def count_predictions_with_text_embeddings() do
    Repo.aggregate(
      from(p in Prediction, where: not p.embedding |> is_nil()),
      :count
    )
  end

  def count_predictions_with_image_embeddings() do
    Repo.aggregate(
      from(p in Prediction, where: not p.image_embedding |> is_nil()),
      :count
    )
  end

  def get_random_prediction_without_text_embeddings() do
    from(p in Prediction,
      where: is_nil(p.embedding) and not is_nil(p.sticker_output) and p.score == 0,
      order_by: fragment("RANDOM()"),
      limit: 1
    )
    |> Repo.one()
  end

  def get_random_prediction_without_image_embeddings() do
    from(p in Prediction,
      where: is_nil(p.image_embedding) and not is_nil(p.sticker_output) and p.score == 0,
      order_by: fragment("RANDOM()"),
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns the list of predictions.

  ## Examples

      iex> list_predictions()
      [%Prediction{}, ...]

  """
  def list_predictions do
    Repo.all(Prediction)
  end

  def list_predictions_with_text_embeddings do
    Repo.all(
      from p in Prediction, where: not is_nil(p.embedding) and not is_nil(p.sticker_output)
    )
  end

  def list_predictions_with_image_embeddings do
    Repo.all(
      from p in Prediction, where: not is_nil(p.image_embedding) and not is_nil(p.sticker_output)
    )
  end

  def paginate(query, page, per_page) do
    offset_by = per_page * page

    query
    |> limit(^per_page)
    |> offset(^offset_by)
  end

  def get_oldest_safe_prediction() do
    from(p in Prediction,
      where: not is_nil(p.sticker_output) and p.is_featured == true,
      order_by: [asc: p.updated_at],
      limit: 1
    )
    |> Repo.one()
  end

  def list_latest_predictions_no_moderation(page, per_page \\ 20) do
    from(p in Prediction,
      where: not is_nil(p.sticker_output) and is_nil(p.is_featured),
      order_by: [desc: p.inserted_at]
    )
    |> paginate(page, per_page)
    |> Repo.all()
  end

  def list_latest_predictions(page, per_page \\ 20) do
    from(p in Prediction,
      where: not is_nil(p.sticker_output),
      order_by: [desc: p.updated_at]
    )
    |> paginate(page, per_page)
    |> Repo.all()
  end

  def list_latest_safe_predictions(page, per_page \\ 20) do
    safe_prediction_query()
    |> paginate(page, per_page)
    |> Repo.all()
  end

  def number_predictions() do
    from(p in Prediction,
      where: not is_nil(p.sticker_output),
      order_by: [desc: p.inserted_at]
    )
    |> Repo.aggregate(:count)
  end

  def number_unmoderated_predictions() do
    from(p in Prediction,
      where: not is_nil(p.sticker_output) and is_nil(p.is_featured),
      order_by: [desc: p.inserted_at]
    )
    |> Repo.aggregate(:count)
  end

  def number_moderated_predictions() do
    safe_prediction_query()
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns the list of predictions for a user.
  """
  def list_user_predictions(user_id) do
    Repo.all(
      from p in Prediction,
        where: p.local_user_id == ^user_id,
        order_by: [desc: p.inserted_at]
    )
  end

  def list_user_predictions(user_id, filters) when is_map(filters) do
    status = Map.get(filters, :status, "all")
    query_text = Map.get(filters, :query, "")

    Prediction
    |> where([p], p.local_user_id == ^user_id)
    |> filter_user_prediction_status(status)
    |> filter_user_prediction_query(query_text)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  def list_user_recent_predictions(user_id, limit \\ 12) do
    Repo.all(
      from p in Prediction,
        where: p.local_user_id == ^user_id,
        order_by: [desc: p.inserted_at],
        limit: ^limit
    )
  end

  def list_user_favorite_predictions(user_id) do
    Repo.all(
      from p in Prediction,
        where: p.local_user_id == ^user_id and p.is_favorite == true,
        order_by: [desc: p.updated_at],
        where: not is_nil(p.sticker_output)
    )
  end

  def user_prediction_counts(user_id) do
    query = from p in Prediction, where: p.local_user_id == ^user_id

    %{
      total: Repo.aggregate(query, :count),
      completed: Repo.aggregate(from(p in query, where: p.status == :succeeded), :count),
      failed: Repo.aggregate(from(p in query, where: p.status == :failed), :count),
      favorites: Repo.aggregate(from(p in query, where: p.is_favorite == true), :count)
    }
  end

  def get_user_prediction!(id, user_id) do
    Repo.get_by!(Prediction, id: id, local_user_id: user_id)
  end

  def delete_user_prediction(id, user_id) do
    id
    |> get_user_prediction!(user_id)
    |> delete_prediction()
  end

  def delete_user_predictions(ids, user_id) when is_list(ids) do
    from(p in Prediction, where: p.local_user_id == ^user_id and p.id in ^ids)
    |> Repo.delete_all()
  end

  def list_user_downloadable_predictions(ids, user_id) when is_list(ids) do
    from(p in Prediction,
      where:
        p.local_user_id == ^user_id and p.id in ^ids and
          not is_nil(p.sticker_output),
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  def toggle_favorite(id, user_id) do
    prediction = get_user_prediction!(id, user_id)
    update_prediction(prediction, %{is_favorite: not prediction.is_favorite})
  end

  def fail_prediction_and_refund(%Prediction{} = prediction) do
    prediction = get_prediction_for_update(prediction)
    should_refund? = not prediction.credit_refunded

    Multi.new()
    |> Multi.update(:prediction, Prediction.changeset(prediction, failed_attrs(prediction)))
    |> Multi.run(:refund, fn _repo, %{prediction: prediction} ->
      if should_refund? do
        case Accounts.refund_credit_by_public_id(prediction.local_user_id) do
          {:ok, _user} -> {:ok, :refunded}
          {:error, :not_found} -> {:ok, :no_account}
        end
      else
        {:ok, :already_refunded}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{prediction: prediction}} -> {:ok, prediction}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def transfer_user_predictions(from_user_id, to_user_id)
      when is_binary(from_user_id) and is_binary(to_user_id) and from_user_id != to_user_id do
    from(p in Prediction, where: p.local_user_id == ^from_user_id)
    |> Repo.update_all(set: [local_user_id: to_user_id])
  end

  def transfer_user_predictions(_from_user_id, _to_user_id), do: {0, nil}

  @doc """
  Gets a single prediction.

  Raises `Ecto.NoResultsError` if the Prediction does not exist.

  ## Examples

      iex> get_prediction!(123)
      %Prediction{}

      iex> get_prediction!(456)
      ** (Ecto.NoResultsError)

  """
  def get_prediction!(id), do: Repo.get!(Prediction, id)

  @doc """
  Creates a prediction.

  ## Examples

      iex> create_prediction(%{field: value})
      {:ok, %Prediction{}}

      iex> create_prediction(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_prediction(attrs \\ %{}) do
    %Prediction{}
    |> Prediction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a prediction.

  ## Examples

      iex> update_prediction(prediction, %{field: new_value})
      {:ok, %Prediction{}}

      iex> update_prediction(prediction, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_prediction(%Prediction{} = prediction, attrs) do
    prediction
    |> Prediction.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a prediction.

  ## Examples

      iex> delete_prediction(prediction)
      {:ok, %Prediction{}}

      iex> delete_prediction(prediction)
      {:error, %Ecto.Changeset{}}

  """
  def delete_prediction(%Prediction{} = prediction) do
    Repo.delete(prediction)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking prediction changes.

  ## Examples

      iex> change_prediction(prediction)
      %Ecto.Changeset{data: %Prediction{}}

  """
  def change_prediction(%Prediction{} = prediction, attrs \\ %{}) do
    Prediction.changeset(prediction, attrs)
  end

  defp image_provider do
    System.get_env("IMAGE_PROVIDER", "replicate")
    |> String.downcase()
  end

  defp get_prediction_for_update(%Prediction{id: id}), do: get_prediction!(id)

  defp broadcast(user_id, message),
    do: Phoenix.PubSub.broadcast(Sticker.PubSub, "user:#{user_id}", message)

  defp failed_attrs(%Prediction{credit_refunded: true}), do: %{status: :failed}
  defp failed_attrs(_prediction), do: %{status: :failed, credit_refunded: true}

  defp filter_user_prediction_status(query, "completed"),
    do: where(query, [p], p.status == :succeeded)

  defp filter_user_prediction_status(query, "processing"),
    do: where(query, [p], p.status in [:starting, :processing, :moderation_succeeded])

  defp filter_user_prediction_status(query, "failed"),
    do: where(query, [p], p.status == :failed)

  defp filter_user_prediction_status(query, "favorites"),
    do: where(query, [p], p.is_favorite == true)

  defp filter_user_prediction_status(query, _status), do: query

  defp filter_user_prediction_query(query, text) when is_binary(text) do
    text = String.trim(text)

    if text == "" do
      query
    else
      where(query, [p], ilike(p.prompt, ^"%#{text}%"))
    end
  end

  defp filter_user_prediction_query(query, _text), do: query
end
