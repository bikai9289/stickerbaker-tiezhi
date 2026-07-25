defmodule StickerWeb.PredictionRetry do
  alias Sticker.MediaDownload
  alias Sticker.Predictions

  def start(%{model: "face-to-sticker", source_image_url: source_image_url} = prediction)
      when is_binary(source_image_url) do
    case MediaDownload.fetch(source_image_url) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        content_type =
          prediction.source_image_content_type ||
            header_content_type(headers) ||
            "image/png"

        image_uri =
          body
          |> Base.encode64()
          |> Sticker.Utils.base64_to_data_uri(content_type)

        case Sticker.ImageSafety.review(image_uri) do
          :ok ->
            Predictions.gen_face_to_sticker(
              prediction.prompt,
              image_uri,
              prediction.local_user_id,
              prediction.id
            )

          {:error, :unsafe_image} ->
            Predictions.fail_prediction_and_refund(
              prediction,
              :moderation,
              "Stored source image failed safety review"
            )

          {:error, reason} ->
            Predictions.fail_prediction_and_refund(prediction, :moderation, reason)
        end

      _error ->
        Predictions.fail_prediction_and_refund(
          prediction,
          :upload,
          "Stored source image could not be loaded"
        )
    end
  end

  def start(prediction) do
    Predictions.moderate(prediction.prompt, prediction.local_user_id, prediction.id)
  end

  defp header_content_type(headers) do
    Enum.find_value(headers, fn
      {"content-type", [value | _]} -> value
      {"content-type", value} when is_binary(value) -> value
      {"Content-Type", value} when is_binary(value) -> value
      _header -> nil
    end)
  end
end
