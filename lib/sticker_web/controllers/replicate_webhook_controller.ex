defmodule StickerWeb.ReplicateWebhookController do
  use StickerWeb, :controller
  alias Sticker.Predictions
  require Logger

  @annoying_users ["lt3hjkan30umvl86oz2", "lt3ihfm35457xftgd3r", "lt3ihohmy96n9ofb5m"]

  def handle(conn, params) do
    handle_webhook(conn, params)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end

  def handle_webhook(
        conn,
        %{
          "status" => status,
          "output" => output,
          "user_id" => user_id,
          "prediction_id" => prediction_id,
          "model" => "fofr/prompt-classifier"
        }
      ) do
    rating = Sticker.Utils.parse_prompt_classifier_output(output)

    if user_id in @annoying_users do
      broadcast(user_id, {:moderation_failed, "Something went wrong...try again?"})
    else
      case status do
        "succeeded" ->
          prediction = Predictions.get_prediction!(prediction_id)

          if prediction.status != :canceled do
            {:ok, prediction} =
              Predictions.update_prediction(prediction, %{
                moderator: "fofr/prompt-classifier",
                moderation_score: rating,
                status: :moderation_succeeded
              })

            broadcast(user_id, {:moderation_complete, prediction})

            # automatically kick off gen image step
            if rating <= 5 do
              Predictions.gen_image(prediction.prompt, user_id, prediction_id)
            else
              {:ok, prediction} =
                Predictions.fail_prediction_and_refund(
                  prediction,
                  :moderation,
                  "Safety rating too low: #{10 - rating}/10"
                )

              broadcast(user_id, {:prediction_failed, prediction})
              broadcast(user_id, {:moderation_failed, "AI generated safety rating: #{10 - rating}/10"})
            end
          end

        "failed" ->
          prediction = prediction_id |> Predictions.get_prediction!()

          if prediction.status != :canceled do
            {:ok, prediction} =
              Predictions.fail_prediction_and_refund(prediction, :moderation, "Replicate moderation failed")

            broadcast(user_id, {:prediction_failed, prediction})
            broadcast(user_id, {:moderation_failed, "Something went wrong...try again?"})
          end

        status ->
          IO.inspect("status is... #{status}")
      end
    end

    conn
  end

  def handle_webhook(
        conn,
        %{
          "status" => status,
          "output" => output,
          "id" => uuid,
          "user_id" => user_id,
          "model" => _model,
          "prediction_id" => prediction_id
        }
      ) do
    prediction = prediction_id |> Predictions.get_prediction!()

    case status do
      "succeeded" ->
        if prediction.status != :canceled do
          complete_prediction(prediction, prediction_id, output, uuid, user_id)
        end

      "failed" ->
        if prediction.status != :canceled do
          {:ok, prediction} =
            prediction
            |> Predictions.update_prediction(%{uuid: uuid})
            |> case do
              {:ok, prediction} ->
                Predictions.fail_prediction_and_refund(prediction, :generation, "Replicate image failed")

              error -> error
            end

          broadcast(user_id, {:prediction_failed, prediction})
        end

      "processing" ->
        if prediction.status != :canceled do
          {:ok, prediction} =
            Predictions.update_prediction(prediction, %{status: :processing})

          broadcast(user_id, {:prediction_loading, prediction})
        end

      status ->
        IO.puts("status is... #{status}")
    end

    conn
  end

  # catch-all handle webhook
  def handle_webhook(conn, _params) do
    Logger.warning("uncaught webhook")

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
  end

  defp broadcast(user_id, message),
    do: Phoenix.PubSub.broadcast(Sticker.PubSub, "user:#{user_id}", message)

  defp output_file_name(prediction_id, "face-to-sticker"),
    do: "prediction-#{prediction_id}-sticker.png"

  defp output_file_name(prediction_id, _model),
    do: "prediction-#{prediction_id}-sticker.webp"

  defp complete_prediction(prediction, prediction_id, output, uuid, user_id) do
    file_name = output_file_name(prediction_id, prediction.model)
    content_type = Sticker.Utils.content_type_for(file_name)

    r2_url = Sticker.Utils.save_r2(file_name, output_url(output), content_type)

    {:ok, prediction} =
      Predictions.update_prediction(prediction, %{
        uuid: uuid,
        sticker_output: r2_url,
        output_format: Sticker.Utils.output_format(file_name),
        output_content_type: content_type,
        status: :succeeded,
        failure_reason: nil,
        failure_stage: nil
      })

    broadcast(user_id, {:prediction_completed, prediction})

    Phoenix.PubSub.broadcast(
      Sticker.PubSub,
      "prediction-firehose",
      {:new_prediction, prediction}
    )
  rescue
    reason ->
      {:ok, prediction} = Predictions.fail_prediction_and_refund(prediction, :storage, reason)
      broadcast(user_id, {:prediction_failed, prediction})
  end

  defp output_url([_head | _tail] = output), do: List.last(output)
  defp output_url(output) when is_binary(output), do: output
  defp output_url(%{"url" => url}) when is_binary(url), do: url
  defp output_url(%{url: url}) when is_binary(url), do: url
end
