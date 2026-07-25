defmodule StickerWeb.StickerBatchDownloadController do
  use StickerWeb, :controller

  alias Sticker.MediaDownload
  alias Sticker.Predictions
  alias StickerWeb.SEO, as: PageSEO

  def show(conn, %{"ids" => ids_param} = params) do
    conn =
      SEO.assign(
        conn,
        PageSEO.noindex("/stickers/download",
          title: "Sticker Batch Download",
          description: "Download generated AI stickers as a ZIP file."
        )
      )

    ids = parse_ids(ids_param)
    format = requested_format(params["format"])
    local_user_id = get_session(conn, :local_user_id) || get_session(conn, "local_user_id")

    with true <- local_user_id not in [nil, ""],
         predictions when predictions != [] <-
           Predictions.list_user_downloadable_predictions(ids, local_user_id),
         {:ok, files} <- fetch_files(predictions, format),
         {:ok, zip_binary} <- create_zip(files) do
      conn
      |> put_resp_content_type("application/zip")
      |> send_download({:binary, zip_binary}, filename: "stickers.zip")
    else
      _ ->
        conn
        |> put_flash(:error, "No completed stickers are ready for batch download.")
        |> redirect(to: ~p"/stickers")
    end
  end

  def show(conn, _params) do
    conn
    |> put_flash(:error, "Select completed stickers before downloading.")
    |> redirect(to: ~p"/stickers")
  end

  defp parse_ids(ids_param) when is_binary(ids_param) do
    ids_param
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn id ->
      case Integer.parse(id) do
        {integer, ""} -> [integer]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp requested_format("png"), do: "png"
  defp requested_format("webp"), do: "webp"
  defp requested_format(_format), do: "original"

  defp fetch_files(predictions, format) do
    predictions
    |> Enum.reduce_while({:ok, []}, fn prediction, {:ok, files} ->
      case MediaDownload.fetch(prediction.sticker_output) do
        {:ok, %{status: 200, body: body}} ->
          with {:ok, body, extension} <- maybe_convert(body, prediction, format) do
            file_name = file_name(prediction, extension)
            {:cont, {:ok, [{String.to_charlist(file_name), body} | files]}}
          else
            _ -> {:halt, :error}
          end

        _ ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, files} -> {:ok, Enum.reverse(files)}
      :error -> :error
    end
  end

  defp create_zip(files) do
    case :zip.create('stickers.zip', files, [:memory]) do
      {:ok, {'stickers.zip', zip_binary}} -> {:ok, zip_binary}
      {:ok, zip_binary} when is_binary(zip_binary) -> {:ok, zip_binary}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_convert(body, prediction, "original") do
    {:ok, body, source_extension(prediction)}
  end

  defp maybe_convert(body, prediction, requested_extension) do
    source_extension = source_extension(prediction)

    if source_extension == requested_extension do
      {:ok, body, requested_extension}
    else
      with {:ok, body} <-
             Sticker.ImageConverter.convert(body, source_extension, requested_extension) do
        {:ok, body, requested_extension}
      end
    end
  end

  defp file_name(prediction, extension), do: "sticker-#{prediction.id}.#{extension}"

  defp source_extension(prediction) do
    extension =
      prediction.output_format ||
        prediction.sticker_output
        |> URI.parse()
        |> Map.get(:path)
        |> Path.extname()
        |> String.trim_leading(".")

    if extension in [nil, ""], do: "png", else: extension
  end
end
