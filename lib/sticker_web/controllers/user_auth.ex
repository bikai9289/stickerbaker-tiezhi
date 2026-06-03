defmodule StickerWeb.UserAuth do
  import Phoenix.Component, only: [assign: 3]
  import Plug.Conn, only: [get_session: 2]

  alias Sticker.Accounts

  def fetch_current_user(conn, _opts) do
    user =
      conn
      |> get_session(:user_id)
      |> Accounts.get_user()

    Plug.Conn.assign(conn, :current_user, user)
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    user =
      session
      |> Map.get("user_id")
      |> Accounts.get_user()

    {:cont, assign(socket, :current_user, user)}
  end
end
