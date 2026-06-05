defmodule Sticker.ImageUpload do
  @jpeg "image/jpeg"
  @png "image/png"

  def data_uri(bytes, content_type) when is_binary(bytes) and is_binary(content_type) do
    if valid_image_bytes?(bytes, content_type) do
      {:ok, Sticker.Utils.base64_to_data_uri(Base.encode64(bytes), content_type)}
    else
      {:error, :invalid_image}
    end
  end

  def data_uri(_bytes, _content_type), do: {:error, :invalid_image}

  def valid_image_bytes?(<<0xFF, 0xD8, _rest::binary>>, @jpeg), do: true

  def valid_image_bytes?(
        <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>,
        @png
      ),
      do: true

  def valid_image_bytes?(_bytes, _type), do: false
end
