defmodule StickerWeb.HomeLiveTest do
  use ExUnit.Case, async: true

  alias StickerWeb.HomeLive

  test "face sticker uploads can submit without a typed prompt" do
    assert HomeLive.face_sticker_prompt("   ", true) ==
             "a cute, clean portrait sticker with a white background"
  end

  test "text sticker submissions still use the typed prompt" do
    assert HomeLive.face_sticker_prompt("  kawaii robot  ", false) == "kawaii robot"
  end

  test "home page template has a face sticker generation action" do
    assert File.read!("lib/sticker_web/live/home_live.html.heex") =~
             "Generate Face Sticker"
  end
end
