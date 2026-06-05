defmodule Sticker.ImageUploadTest do
  use ExUnit.Case, async: true

  alias Sticker.ImageUpload

  test "data_uri/2 accepts JPEG bytes" do
    bytes = <<0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x01, 0x00, 0x01, 0x03, 0x00>>

    assert {:ok, data_uri} = ImageUpload.data_uri(bytes, "image/jpeg")
    assert String.starts_with?(data_uri, "data:image/jpeg;base64,")
  end

  test "data_uri/2 accepts PNG bytes" do
    bytes =
      <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, "IHDR", 0x00,
        0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00>>

    assert {:ok, data_uri} = ImageUpload.data_uri(bytes, "image/png")
    assert String.starts_with?(data_uri, "data:image/png;base64,")
  end

  test "data_uri/2 rejects spoofed content types" do
    assert {:error, :invalid_image} = ImageUpload.data_uri("not an image", "image/png")
    assert {:error, :invalid_image} = ImageUpload.data_uri(<<0xFF, 0xD8, 0xFF>>, "image/png")
  end

  test "data_uri/2 rejects oversized image dimensions" do
    bytes =
      <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, "IHDR", 0x00,
        0x00, 0x13, 0x88, 0x00, 0x00, 0x13, 0x88, 0x08, 0x02, 0x00, 0x00, 0x00>>

    assert {:error, :invalid_image} = ImageUpload.data_uri(bytes, "image/png")
  end
end
