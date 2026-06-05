defmodule StickerWeb.AbuseProtection do
  import Plug.Conn
  import Phoenix.Controller
  use Phoenix.VerifiedRoutes, endpoint: StickerWeb.Endpoint, router: StickerWeb.Router

  alias Sticker.Accounts
  alias StickerWeb.RateLimiter

  @registration_ip_limit 5
  @registration_window_seconds 24 * 60 * 60
  @auth_ip_limit 30
  @auth_window_seconds 60 * 60

  def client_ip(conn) do
    forwarded_for =
      conn
      |> get_req_header("x-forwarded-for")
      |> List.first()

    forwarded_for
    |> first_forwarded_ip()
    |> case do
      nil -> conn.remote_ip |> :inet.ntoa() |> to_string()
      ip -> ip
    end
  end

  def check_registration(conn) do
    ip = client_ip(conn)

    with :ok <- RateLimiter.check("register:#{ip}", @auth_ip_limit, @auth_window_seconds),
         :ok <- check_daily_signup_count(ip) do
      :ok
    else
      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, "Too many signup attempts from this network. Try again later.")
        |> redirect(to: ~p"/users/register")
        |> halt()
    end
  end

  def captcha_question do
    left = Enum.random(2..9)
    right = Enum.random(2..9)
    %{question: "#{left} + #{right}", answer: Integer.to_string(left + right)}
  end

  def captcha_valid?(params, session_answer) do
    answer =
      params
      |> Map.get("captcha_answer", "")
      |> to_string()
      |> String.trim()

    answer != "" and answer == to_string(session_answer)
  end

  defp check_daily_signup_count(ip) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-@registration_window_seconds, :second)
      |> DateTime.truncate(:second)

    if Accounts.count_signups_since_ip(ip, since) >= @registration_ip_limit do
      {:error, :rate_limited}
    else
      :ok
    end
  end

  defp first_forwarded_ip(nil), do: nil

  defp first_forwarded_ip(value) do
    value
    |> String.split(",", parts: 2)
    |> hd()
    |> String.trim()
    |> case do
      "" -> nil
      ip -> ip
    end
  end
end
