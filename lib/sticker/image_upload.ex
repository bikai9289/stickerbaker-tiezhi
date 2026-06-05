defmodule Sticker.ImageUpload do
  @jpeg "image/jpeg"
  @png "image/png"
  @max_pixels 12_000_000

  def data_uri(bytes, content_type) when is_binary(bytes) and is_binary(content_type) do
    if safe_image?(bytes, content_type) do
      {:ok, Sticker.Utils.base64_to_data_uri(Base.encode64(bytes), content_type)}
    else
      {:error, :invalid_image}
    end
  end

  def data_uri(_bytes, _content_type), do: {:error, :invalid_image}

  def safe_image?(bytes, content_type) do
    valid_image_bytes?(bytes, content_type) and safe_dimensions?(bytes, content_type)
  end

  def valid_image_bytes?(<<0xFF, 0xD8, _rest::binary>>, @jpeg), do: true

  def valid_image_bytes?(
        <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>,
        @png
      ),
      do: true

  def valid_image_bytes?(_bytes, _type), do: false

  defp safe_dimensions?(bytes, @png), do: png_dimensions(bytes) |> within_pixel_limit?()
  defp safe_dimensions?(bytes, @jpeg), do: jpeg_dimensions(bytes) |> within_pixel_limit?()
  defp safe_dimensions?(_bytes, _type), do: false

  defp within_pixel_limit?({width, height}) when width > 0 and height > 0,
    do: width * height <= @max_pixels

  defp within_pixel_limit?(_dimensions), do: false

  defp png_dimensions(
         <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _length::32, "IHDR", width::32,
           height::32, _rest::binary>>
       ),
       do: {width, height}

  defp png_dimensions(_bytes), do: :error

  defp jpeg_dimensions(<<0xFF, 0xD8, rest::binary>>), do: scan_jpeg(rest)
  defp jpeg_dimensions(_bytes), do: :error

  defp scan_jpeg(<<0xFF, marker, _length::16, _precision, height::16, width::16, _rest::binary>>)
       when marker in 0xC0..0xC3,
       do: {width, height}

  defp scan_jpeg(<<0xFF, marker, length::16, rest::binary>>)
       when marker != 0xD9 and length >= 2 do
    skip = length - 2

    if byte_size(rest) >= skip do
      <<_segment::binary-size(skip), next::binary>> = rest
      scan_jpeg(next)
    else
      :error
    end
  end

  defp scan_jpeg(<<_byte, rest::binary>>), do: scan_jpeg(rest)
  defp scan_jpeg(_bytes), do: :error
end
