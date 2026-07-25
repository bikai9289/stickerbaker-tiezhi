defmodule Sticker.PromptInputTest do
  use ExUnit.Case, async: true

  alias Sticker.PromptInput

  test "keeps line breaks inside a single prompt by default" do
    prompt = "A cheerful mascot\nholding a tiny orange umbrella"

    assert {:ok, [^prompt]} = PromptInput.parse(prompt, batch?: false)
  end

  test "splits non-empty lines only when batch mode is enabled" do
    assert {:ok, ["red panda", "blue robot"]} =
             PromptInput.parse(" red panda \n\n blue robot ", batch?: true)
  end

  test "rejects more than five batch prompts instead of silently dropping them" do
    prompt = Enum.map_join(1..6, "\n", &"sticker #{&1}")

    assert {:error, :too_many_prompts} = PromptInput.parse(prompt, batch?: true)
  end

  test "rejects empty and oversized prompts" do
    assert {:error, :empty_prompt} = PromptInput.parse("   ", batch?: false)

    assert {:error, :prompt_too_long} =
             PromptInput.parse(String.duplicate("a", 1001), batch?: false)
  end
end
