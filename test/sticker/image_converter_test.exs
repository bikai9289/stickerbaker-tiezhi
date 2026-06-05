defmodule Sticker.ImageConverterTest do
  use ExUnit.Case, async: true

  alias Sticker.ImageConverter
  alias Sticker.Utils

  test "detects output format and content type from file name" do
    assert Utils.output_format("prediction-1-sticker.webp") == "webp"
    assert Utils.content_type_for("prediction-1-sticker.webp") == "image/webp"
    assert Utils.content_type_for("prediction-1-sticker.png") == "image/png"
  end

  test "returns binary unchanged when requested format matches source format" do
    assert ImageConverter.convert("image-bytes", "png", "png") == {:ok, "image-bytes"}
  end

  test "rejects unsupported formats" do
    assert ImageConverter.convert("image-bytes", "gif", "png") == {:error, :unsupported_format}
  end
end
