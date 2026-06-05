defmodule Sticker.ImageUploadTest do
  use ExUnit.Case, async: true

  alias Sticker.ImageUpload

  test "data_uri/2 accepts JPEG bytes" do
    assert {:ok, data_uri} = ImageUpload.data_uri(<<0xFF, 0xD8, 0xFF, 0x00>>, "image/jpeg")
    assert String.starts_with?(data_uri, "data:image/jpeg;base64,")
  end

  test "data_uri/2 accepts PNG bytes" do
    bytes = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00>>

    assert {:ok, data_uri} = ImageUpload.data_uri(bytes, "image/png")
    assert String.starts_with?(data_uri, "data:image/png;base64,")
  end

  test "data_uri/2 rejects spoofed content types" do
    assert {:error, :invalid_image} = ImageUpload.data_uri("not an image", "image/png")
    assert {:error, :invalid_image} = ImageUpload.data_uri(<<0xFF, 0xD8, 0xFF>>, "image/png")
  end
end
