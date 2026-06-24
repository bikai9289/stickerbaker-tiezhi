defmodule StickerWeb.SessionController do
  use StickerWeb, :controller

  alias StickerWeb.PendingPromptIntent

  def set(conn, %{"local_user_id" => user_id}), do: store_string(conn, :local_user_id, user_id)

  def pending_prompt(conn, %{"prompt" => prompt}) do
    PendingPromptIntent.store_and_redirect(conn, prompt)
  end

  defp store_string(conn, key, value) do
    conn
    |> put_session(key, value)
    |> json("OK!")
  end
end
