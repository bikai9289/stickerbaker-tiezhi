defmodule StickerWeb.SessionController do
  use StickerWeb, :controller

  alias StickerWeb.PendingPromptIntent

  def pending_prompt(conn, %{"prompt" => prompt}) do
    PendingPromptIntent.store_and_redirect(conn, prompt)
  end
end
