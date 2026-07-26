defmodule StickerWeb.GuestIdentity do
  import Plug.Conn

  alias StickerWeb.AbuseProtection

  @cookie "_sticker_guest"
  @max_age 365 * 24 * 60 * 60
  @format ~r/^gst_[A-Za-z0-9_-]{32,}$/
  @legacy_format ~r/^[A-Za-z0-9_-]{6,128}$/

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn, signed: [@cookie])

    guest_user_id =
      valid_cookie(conn.cookies[@cookie]) || migrate_or_create_guest(conn)

    conn
    |> maybe_put_guest_cookie(guest_user_id)
    |> put_session(:guest_user_id, guest_user_id)
    |> put_session(:guest_client_ip, AbuseProtection.client_ip(conn))
    |> put_session(:local_user_id, generation_user_id(conn, guest_user_id))
  end

  defp valid_cookie(value) when is_binary(value) do
    value = String.trim(value)

    if Regex.match?(@format, value) or Regex.match?(@legacy_format, value), do: value
  end

  defp valid_cookie(_value), do: nil

  defp migrate_or_create_guest(conn) do
    if Map.has_key?(conn.req_cookies, @cookie) do
      new_guest_user_id()
    else
      legacy_session_guest(conn) || new_guest_user_id()
    end
  end

  defp legacy_session_guest(%{assigns: %{current_user: nil}} = conn) do
    case get_session(conn, :local_user_id) do
      value when is_binary(value) ->
        value = String.trim(value)
        if Regex.match?(@legacy_format, value), do: value

      _value ->
        nil
    end
  end

  defp legacy_session_guest(_conn), do: nil

  defp new_guest_user_id do
    "gst_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

  defp maybe_put_guest_cookie(%{cookies: %{@cookie => value}} = conn, value), do: conn

  defp maybe_put_guest_cookie(conn, value) do
    put_resp_cookie(conn, @cookie, value,
      sign: true,
      http_only: true,
      same_site: "Lax",
      max_age: @max_age,
      secure: secure_cookie?()
    )
  end

  defp generation_user_id(%{assigns: %{current_user: %{public_id: public_id}}}, _guest_user_id),
    do: public_id

  defp generation_user_id(_conn, guest_user_id), do: guest_user_id

  defp secure_cookie? do
    :sticker
    |> Application.get_env(StickerWeb.Endpoint, [])
    |> Keyword.get(:url, [])
    |> Keyword.get(:scheme) == "https"
  end
end
