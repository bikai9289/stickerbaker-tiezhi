defmodule Sticker.MediaDownload do
  @moduledoc false

  defmodule S3Storage do
    @moduledoc false

    def get_object(bucket, key) do
      bucket
      |> ExAws.S3.get_object(key)
      |> ExAws.request()
    end
  end

  def fetch(url) when is_binary(url) do
    case internal_media_key(url) do
      {:ok, key} -> fetch_from_storage(key)
      :error -> Req.get(url)
    end
  end

  def fetch(_url), do: {:error, :missing_media_url}

  defp fetch_from_storage(key) do
    bucket = System.fetch_env!("BUCKET_NAME")

    case storage().get_object(bucket, key) do
      {:ok, %{status_code: 200, body: body, headers: headers}} ->
        {:ok, %{status: 200, body: body, headers: headers}}

      {:ok, %{status_code: status}} ->
        {:error, {:storage_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp internal_media_key(url) do
    case URI.parse(url).path do
      "/media/" <> key when key != "" -> {:ok, URI.decode(key)}
      _path -> :error
    end
  end

  defp storage do
    Application.get_env(:sticker, :download_storage, S3Storage)
  end
end
