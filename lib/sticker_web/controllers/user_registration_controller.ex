defmodule StickerWeb.UserRegistrationController do
  use StickerWeb, :controller

  alias Sticker.Accounts
  alias StickerWeb.UserSessionController
  alias StickerWeb.SEO, as: PageSEO

  def new(conn, _params) do
    changeset = Accounts.change_user_registration()

    conn
    |> SEO.assign(
      PageSEO.noindex("/users/register",
        title: "Create Account",
        description: "Create an AI Sticker Maker account to manage credits and sticker history."
      )
    )
    |> render(:new, changeset: changeset, page_title: "Create Account")
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Account created successfully.")
        |> UserSessionController.log_in_user(user)

      {:error, changeset} ->
        conn
        |> SEO.assign(
          PageSEO.noindex("/users/register",
            title: "Create Account",
            description: "Create an AI Sticker Maker account to manage credits and sticker history."
          )
        )
        |> render(:new, changeset: changeset, page_title: "Create Account")
    end
  end
end
