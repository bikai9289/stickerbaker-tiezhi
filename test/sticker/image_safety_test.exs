defmodule Sticker.ImageSafetyTest do
  use ExUnit.Case, async: false

  alias Sticker.ImageSafety

  test "review/1 allows images when OpenAI is not configured" do
    original_key = System.get_env("OPENAI_API_KEY")
    System.delete_env("OPENAI_API_KEY")

    try do
      assert :ok = ImageSafety.review("data:image/png;base64,abc")
    after
      if original_key, do: System.put_env("OPENAI_API_KEY", original_key)
    end
  end

  test "parse_review_response/1 accepts safe output" do
    response = %{"output" => [%{"content" => [%{"text" => "SAFE"}]}]}

    assert :ok = ImageSafety.parse_review_response(response)
  end

  test "parse_review_response/1 rejects unsafe output" do
    response = %{"output" => [%{"content" => [%{"text" => "UNSAFE"}]}]}

    assert {:error, :unsafe_image} = ImageSafety.parse_review_response(response)
  end

  test "review/1 allows uploads when the safety service is unavailable" do
    original_key = System.get_env("OPENAI_API_KEY")
    original_url = System.get_env("OPENAI_BASE_URL")

    System.put_env("OPENAI_API_KEY", "test-key")
    System.put_env("OPENAI_BASE_URL", "http://127.0.0.1:1/v1")

    try do
      assert :ok = ImageSafety.review("data:image/png;base64,abc")
    after
      restore_env("OPENAI_API_KEY", original_key)
      restore_env("OPENAI_BASE_URL", original_url)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
