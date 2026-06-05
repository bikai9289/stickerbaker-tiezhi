defmodule StickerWeb.StickerDownloadController do
  use StickerWeb, :controller

  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO

  def show(conn, %{"id" => id} = params) do
    prediction = Predictions.get_prediction!(id)

    conn =
      SEO.assign(
        conn,
        PageSEO.noindex("/sticker/#{prediction.id}/download",
          title: "Sticker Download",
          description: "Download a generated AI sticker file."
        )
      )

    with output when is_binary(output) <- prediction.sticker_output,
         {:ok, %{status: 200, body: body, headers: headers}} <- Req.get(output) do
      extension = requested_extension(params["format"], output)
      content_type = content_type(headers, extension)

      conn
      |> put_resp_content_type(content_type)
      |> send_download({:binary, body}, filename: "sticker-#{prediction.id}.#{extension}")
    else
      _ ->
        conn
        |> put_flash(:error, "Sticker download is not ready yet.")
        |> redirect(to: ~p"/sticker/#{prediction.id}")
    end
  end

  defp requested_extension("webp", _output), do: "webp"
  defp requested_extension("png", _output), do: "png"

  defp requested_extension(_format, output) do
    output
    |> URI.parse()
    |> Map.get(:path)
    |> Path.extname()
    |> String.trim_leading(".")
    |> case do
      "" -> "png"
      extension -> extension
    end
  end

  defp content_type(headers, "webp"), do: header_content_type(headers) || "image/webp"
  defp content_type(headers, "png"), do: header_content_type(headers) || "image/png"
  defp content_type(headers, _extension), do: header_content_type(headers) || "application/octet-stream"

  defp header_content_type(headers) do
    Enum.find_value(headers, fn
      {"content-type", value} -> value
      {"Content-Type", value} -> value
      _header -> nil
    end)
  end
end
