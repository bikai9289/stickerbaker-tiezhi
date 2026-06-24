defmodule StickerWeb.UserSessionController do
  use StickerWeb, :controller

  alias Sticker.Accounts
  alias Sticker.Predictions
  alias StickerWeb.PendingPromptIntent
  alias StickerWeb.SEO, as: PageSEO

  def new(conn, _params) do
    conn
    |> SEO.assign(
      PageSEO.noindex("/users/log-in",
        title: "Sign In",
        description:
          "Sign in to AI Sticker Maker to manage credits, sticker history, and downloads."
      )
    )
    |> render(:new, page_title: "Sign In")
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        {conn, redirect_opts} = PendingPromptIntent.login_redirect_opts(conn)
        log_in_user(conn, user, redirect_opts)

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid email or password.")
        |> SEO.assign(
          PageSEO.noindex("/users/log-in",
            title: "Sign In",
            description:
              "Sign in to AI Sticker Maker to manage credits, sticker history, and downloads."
          )
        )
        |> render(:new, page_title: "Sign In", email: email)
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Signed out successfully.")
    |> redirect(to: ~p"/")
  end

  def log_in_user(conn, user, opts \\ []) do
    previous_user_id = get_session(conn, :local_user_id)
    Predictions.transfer_user_predictions(previous_user_id, user.public_id)

    conn =
      conn
      |> renew_session()
      |> put_session(:user_id, user.id)
      |> put_session(:local_user_id, user.public_id)
      |> put_flash(:info, Keyword.get(opts, :info, "Signed in successfully."))

    conn =
      case Keyword.fetch(opts, :error) do
        {:ok, error} -> put_flash(conn, :error, error)
        :error -> conn
      end

    redirect(conn, to: Keyword.get(opts, :redirect_to, ~p"/"))
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
