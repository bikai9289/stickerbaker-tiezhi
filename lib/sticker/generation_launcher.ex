defmodule Sticker.GenerationLauncher do
  @moduledoc false

  alias Phoenix.PubSub
  alias Replicate.Predictions.Prediction, as: RemotePrediction
  alias Sticker.Predictions
  alias Sticker.Predictions.Prediction

  @stale_after_seconds 5 * 60

  def start_text(%Prediction{} = prediction) do
    start_task(prediction, :moderation_start, fn ->
      provider().moderate(prediction.prompt, prediction.local_user_id, prediction.id)
    end)
  end

  def start_face(%Prediction{} = prediction, image_uri) when is_binary(image_uri) do
    start_task(prediction, :generation_start, fn ->
      provider().gen_face_to_sticker(
        prediction.prompt,
        image_uri,
        prediction.local_user_id,
        prediction.id
      )
    end)
  end

  def start_image(%Prediction{} = prediction) do
    Task.Supervisor.start_child(Sticker.GenerationTaskSupervisor, fn ->
      safe_start_image(prediction)
    end)
  end

  def resume_stale(
        %Prediction{status: :starting, model: model, updated_at: updated_at} = prediction
      )
      when model != "face-to-sticker" and not is_nil(updated_at) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-@stale_after_seconds, :second)

    if NaiveDateTime.compare(updated_at, cutoff) == :lt do
      case Predictions.claim_stale_starting_prediction(prediction.id, cutoff) do
        {:ok, claimed_prediction} -> start_text(claimed_prediction)
        :ignored -> :ignored
      end
    else
      :ignored
    end
  end

  def resume_stale(
        %Prediction{status: :moderation_succeeded, uuid: nil, updated_at: updated_at} = prediction
      )
      when not is_nil(updated_at) do
    cutoff = stale_cutoff()

    if NaiveDateTime.compare(updated_at, cutoff) == :lt do
      case Predictions.claim_stale_moderated_prediction(prediction.id, cutoff) do
        {:ok, claimed_prediction} -> start_image(claimed_prediction)
        :ignored -> :ignored
      end
    else
      :ignored
    end
  end

  def resume_stale(_prediction), do: :ignored

  defp start_task(prediction, failure_stage, fun) do
    Task.Supervisor.start_child(Sticker.GenerationTaskSupervisor, fn ->
      safe_start(prediction, failure_stage, fun)
    end)
  end

  defp safe_start(prediction, failure_stage, fun) do
    case fun.() do
      {:error, reason} -> fail_start_and_broadcast(prediction, failure_stage, reason)
      _response -> :ok
    end
  rescue
    reason -> fail_start_and_broadcast(prediction, failure_stage, reason)
  end

  defp safe_start_image(prediction) do
    case provider().gen_image(
           prediction.prompt,
           prediction.local_user_id,
           prediction.id
         ) do
      {:ok, %RemotePrediction{id: uuid}} when is_binary(uuid) ->
        case Predictions.mark_generation_started(prediction.id, uuid) do
          {:ok, started_prediction} ->
            PubSub.broadcast(
              Sticker.PubSub,
              "user:#{prediction.local_user_id}",
              {:prediction_loading, started_prediction}
            )

          :ignored ->
            :ok
        end

      {:error, reason} ->
        fail_start_and_broadcast(prediction, :generation_start, reason)

      _response ->
        :ok
    end
  rescue
    reason -> fail_start_and_broadcast(prediction, :generation_start, reason)
  end

  defp fail_start_and_broadcast(prediction, failure_stage, reason) do
    {:ok, prediction} = Predictions.fail_prediction_and_refund(prediction, failure_stage, reason)

    PubSub.broadcast(
      Sticker.PubSub,
      "user:#{prediction.local_user_id}",
      {:prediction_failed, prediction}
    )

    :ok
  end

  defp provider do
    Application.get_env(:sticker, :generation_provider, Predictions)
  end

  defp stale_cutoff do
    NaiveDateTime.utc_now() |> NaiveDateTime.add(-@stale_after_seconds, :second)
  end
end
