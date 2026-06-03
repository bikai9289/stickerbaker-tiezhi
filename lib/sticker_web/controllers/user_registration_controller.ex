defmodule StickerWeb.UserRegistrationController do
  use StickerWeb, :controller

  alias Sticker.Accounts
  alias StickerWeb.UserSessionController

  def new(conn, _params) do
    changeset = Accounts.change_user_registration()
    render(conn, :new, changeset: changeset, page_title: "Create Account")
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Account created successfully.")
        |> UserSessionController.log_in_user(user)

      {:error, changeset} ->
        render(conn, :new, changeset: changeset, page_title: "Create Account")
    end
  end
end
