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
      extension = requested_extension(params["format"], prediction, output)
      content_type = content_type(headers, prediction, extension)

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

  defp requested_extension("webp", _prediction, _output), do: "webp"
  defp requested_extension("png", _prediction, _output), do: "png"

  defp requested_extension(_format, %{output_format: format}, _output)
       when is_binary(format) and format != "",
       do: format

  defp requested_extension(_format, _prediction, output) do
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

  defp content_type(_headers, %{output_content_type: content_type}, _extension)
       when is_binary(content_type) and content_type != "",
       do: content_type

  defp content_type(headers, _prediction, "webp"), do: header_content_type(headers) || "image/webp"
  defp content_type(headers, _prediction, "png"), do: header_content_type(headers) || "image/png"

  defp content_type(headers, _prediction, _extension),
    do: header_content_type(headers) || "application/octet-stream"

  defp header_content_type(headers) do
    Enum.find_value(headers, fn
      {"content-type", [value | _]} -> value
      {"content-type", value} -> value
      {"Content-Type", [value | _]} -> value
      {"Content-Type", value} -> value
      _header -> nil
    end)
  end
end
