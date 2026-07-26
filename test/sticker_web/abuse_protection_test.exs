defmodule StickerWeb.AbuseProtectionTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias StickerWeb.AbuseProtection

  test "uses the right-most valid forwarded IP appended by the trusted proxy" do
    conn =
      Plug.Test.conn(:get, "/")
      |> put_req_header("x-forwarded-for", "203.0.113.9, 198.51.100.7")

    assert AbuseProtection.client_ip(conn) == "198.51.100.7"
  end

  test "ignores invalid forwarded values and falls back to remote_ip" do
    conn =
      Plug.Test.conn(:get, "/")
      |> Map.put(:remote_ip, {192, 0, 2, 44})
      |> put_req_header("x-forwarded-for", "spoofed.example, not-an-ip")

    assert AbuseProtection.client_ip(conn) == "192.0.2.44"
  end

  test "canonicalizes a valid forwarded IPv6 address" do
    conn =
      Plug.Test.conn(:get, "/")
      |> put_req_header("x-forwarded-for", "203.0.113.9, 2001:0db8:0:0:0:0:0:1")

    assert AbuseProtection.client_ip(conn) == "2001:db8::1"
  end
end
