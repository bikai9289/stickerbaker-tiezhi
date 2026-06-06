defmodule StickerWeb.MediaController do
  use StickerWeb, :controller

  alias Sticker.Predictions

  def show(conn, %{"key" => key_parts}) when is_list(key_parts) do
    key = Path.join(key_parts)

    with %{} = prediction <- Predictions.get_prediction_by_media_key(key),
         false <- Predictions.viewable_by?(prediction, conn.assigns[:current_user], get_session(conn, :local_user_id)) do
      send_resp(conn, 404, "not found")
    else
      _allowed ->
        send_media(conn, key)
    end
  end

  defp send_media(conn, key) do
    bucket = System.fetch_env!("BUCKET_NAME")

    case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
      {:ok, %{status_code: 200, body: body, headers: headers}} ->
        conn
        |> put_resp_content_type(content_type(headers, key))
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_resp(200, body)

      _error ->
        send_resp(conn, 404, "not found")
    end
  end

  defp content_type(headers, key) do
    header_content_type(headers) || Sticker.Utils.content_type_for(key)
  end

  defp header_content_type(headers) do
    Enum.find_value(headers, fn
      {"content-type", value} when is_binary(value) -> value
      {"content-type", [value | _]} -> value
      {"Content-Type", value} when is_binary(value) -> value
      {"Content-Type", [value | _]} -> value
      _header -> nil
    end)
  end
end
