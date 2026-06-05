defmodule Sticker.ImageConverter do
  @formats ~w(png webp)

  def convert(binary, from_format, to_format)
      when is_binary(binary) and is_binary(from_format) and is_binary(to_format) do
    from_format = normalize_format(from_format)
    to_format = normalize_format(to_format)

    cond do
      from_format == to_format ->
        {:ok, binary}

      from_format in @formats and to_format in @formats ->
        convert_with_imagemagick(binary, from_format, to_format)

      true ->
        {:error, :unsupported_format}
    end
  end

  def content_type("webp"), do: "image/webp"
  def content_type("png"), do: "image/png"

  def supported?(format), do: normalize_format(format) in @formats

  defp convert_with_imagemagick(binary, from_format, to_format) do
    tmp_dir = System.tmp_dir!()
    unique = System.unique_integer([:positive])
    input_path = Path.join(tmp_dir, "sticker-#{unique}.#{from_format}")
    output_path = Path.join(tmp_dir, "sticker-#{unique}.#{to_format}")

    with :ok <- File.write(input_path, binary),
         {:ok, command} <- imagemagick_command(),
         {_output, 0} <- System.cmd(command, [input_path, output_path], stderr_to_stdout: true),
         {:ok, converted} <- File.read(output_path) do
      {:ok, converted}
    else
      {_output, _status} -> {:error, :conversion_failed}
      error -> error
    after
      File.rm(input_path)
      File.rm(output_path)
    end
  end

  defp imagemagick_command do
    cond do
      command = System.find_executable("magick") -> {:ok, command}
      command = System.find_executable("convert") -> {:ok, command}
      true -> {:error, :imagemagick_unavailable}
    end
  end

  defp normalize_format(format) do
    format
    |> to_string()
    |> String.trim()
    |> String.trim_leading(".")
    |> String.downcase()
  end
end
