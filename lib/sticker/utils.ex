defmodule Sticker.Utils do
  require Logger

  def parse_prompt_classifier_output(output) do
    output
    |> Enum.join()
    |> String.trim()
    |> Float.parse()
    |> case do
      {float, _str} -> float |> round()
      :error -> 10
    end
  end

  def save_r2(file_name, image_url, content_type \\ nil) do
    response = Req.get!(image_url)

    content_type =
      content_type || header_content_type(response.headers) || content_type_for(file_name)

    save_r2_binary(file_name, response.body, content_type)
  end

  def save_r2_base64(file_name, base64, content_type \\ nil) do
    image_binary = Base.decode64!(base64)
    save_r2_binary(file_name, image_binary, content_type || content_type_for(file_name))
  end

  def save_r2_upload(file_name, image_binary, content_type) when is_binary(image_binary) do
    save_r2_binary(file_name, image_binary, content_type || content_type_for(file_name))
  end

  def output_format(file_name) do
    file_name
    |> Path.extname()
    |> String.trim_leading(".")
    |> String.downcase()
    |> case do
      "" -> "png"
      extension -> extension
    end
  end

  def content_type_for(file_name) do
    case output_format(file_name) do
      "webp" -> "image/webp"
      "jpg" -> "image/jpeg"
      "jpeg" -> "image/jpeg"
      "png" -> "image/png"
      _extension -> "application/octet-stream"
    end
  end

  defp save_r2_binary(file_name, image_binary, content_type) do
    bucket = System.fetch_env!("BUCKET_NAME")

    %{status_code: 200} =
      bucket
      |> ExAws.S3.put_object(file_name, image_binary,
        content_type: content_type,
        acl: :public_read
      )
      |> ExAws.request!()

    "#{System.get_env("AWS_PUBLIC_URL")}/#{bucket}/#{file_name}"
  end

  defp header_content_type(headers) do
    Enum.find_value(headers, fn
      {"content-type", [value | _]} -> value
      {"content-type", value} when is_binary(value) -> value
      {"Content-Type", value} when is_binary(value) -> value
      _header -> nil
    end)
  end

  def get_host() do
    case StickerWeb.Endpoint.host() do
      "localhost" ->
        Logger.warning("WE ARE IN LOCALHOST — IS NGROK SETUP?")
        System.fetch_env!("NGROK_URL")

      host ->
        "https://#{host}"
    end
  end

  def base64_to_data_uri(base64, mime_type \\ "image/png") do
    "data:#{mime_type};base64," <> base64
  end
end
