defmodule StickerWeb.UserRegistrationController do
  use StickerWeb, :controller

  alias Sticker.Accounts
  alias StickerWeb.AbuseProtection
  alias StickerWeb.PendingPromptIntent
  alias StickerWeb.UserSessionController
  alias StickerWeb.SEO, as: PageSEO

  def new(conn, _params) do
    changeset = Accounts.change_user_registration()
    captcha = AbuseProtection.captcha_question()

    conn
    |> put_session(:captcha_answer, captcha.answer)
    |> SEO.assign(
      PageSEO.noindex("/users/register",
        title: "Create Account",
        description: "Create an AI Sticker Maker account to manage credits and sticker history."
      )
    )
    |> render(:new,
      changeset: changeset,
      captcha_question: captcha.question,
      pending_prompt?: PendingPromptIntent.pending?(conn),
      page_title: "Create Account"
    )
  end

  def create(conn, %{"user" => user_params} = params) do
    with :ok <- AbuseProtection.check_registration(conn),
         true <- AbuseProtection.captcha_valid?(params, get_session(conn, :captcha_answer)) do
      user_params =
        user_params
        |> Map.put("signup_ip", AbuseProtection.client_ip(conn))
        |> put_signup_guest_user_id(
          get_session(conn, :guest_user_id) || get_session(conn, :local_user_id)
        )

      case Accounts.register_user(user_params) do
        {:ok, user} ->
          {conn, redirect_opts} = PendingPromptIntent.login_redirect_opts(conn)

          Accounts.send_confirmation_email(user, fn token ->
            url(~p"/users/confirm/#{token}")
          end)

          conn
          |> delete_session(:captcha_answer)
          |> put_flash(
            :info,
            "Account created. Confirm your email to unlock your remaining free credits."
          )
          |> UserSessionController.log_in_user(user, redirect_opts)

        {:error, changeset} ->
          render_new(conn, changeset)
      end
    else
      false ->
        conn
        |> put_flash(:error, "Captcha answer is incorrect.")
        |> render_new(Accounts.change_user_registration(user_params))

      %Plug.Conn{} = halted_conn ->
        halted_conn
    end
  end

  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Email confirmed. Your 3 free credits are ready.")
        |> UserSessionController.log_in_user(user, redirect_to: ~p"/?registration=confirmed")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Confirmation link is invalid or already used.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp render_new(conn, changeset) do
    captcha = AbuseProtection.captcha_question()

    conn
    |> put_session(:captcha_answer, captcha.answer)
    |> SEO.assign(
      PageSEO.noindex("/users/register",
        title: "Create Account",
        description: "Create an AI Sticker Maker account to manage credits and sticker history."
      )
    )
    |> render(:new,
      changeset: changeset,
      captcha_question: captcha.question,
      pending_prompt?: PendingPromptIntent.pending?(conn),
      page_title: "Create Account"
    )
  end

  defp put_signup_guest_user_id(user_params, guest_user_id) when is_binary(guest_user_id) do
    Map.put(user_params, "signup_guest_user_id", guest_user_id)
  end

  defp put_signup_guest_user_id(user_params, _guest_user_id), do: user_params
end
