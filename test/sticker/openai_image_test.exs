defmodule Sticker.OpenAIImageTest do
  use ExUnit.Case, async: true

  alias Sticker.OpenAIImage

  test "parse_response/1 returns the image generation result" do
    response = %{
      "output" => [
        %{"type" => "message", "content" => []},
        %{"type" => "image_generation_call", "result" => "base64-image"}
      ]
    }

    assert OpenAIImage.parse_response(response) == {:ok, "base64-image"}
  end

  test "parse_response/1 returns an error when no image exists" do
    assert OpenAIImage.parse_response(%{"output" => []}) == {:error, :missing_image_result}
  end
end
