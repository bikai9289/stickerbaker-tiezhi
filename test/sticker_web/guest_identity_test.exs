defmodule StickerWeb.GuestIdentityTest do
  use StickerWeb.ConnCase, async: true

  import Sticker.AccountsFixtures
  import Sticker.PredictionsFixtures

  alias Sticker.GuestTrials
  alias Sticker.Predictions

  test "first browser request receives a signed HttpOnly guest cookie", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert [cookie] =
             conn
             |> get_resp_header("set-cookie")
             |> Enum.filter(&String.starts_with?(&1, "_sticker_guest="))

    assert cookie =~ "HttpOnly"
    assert cookie =~ "SameSite=Lax"
    refute cookie =~ "guest_user_id="
  end

  test "legacy signed-session guest identity seeds the new cookie once", %{conn: conn} do
    legacy_guest_id = "legacy_guest_123"

    conn =
      conn
      |> init_test_session(%{local_user_id: legacy_guest_id})
      |> get(~p"/")

    assert get_session(conn, :guest_user_id) == legacy_guest_id
    assert get_session(conn, :local_user_id) == legacy_guest_id
    assert Map.has_key?(conn.resp_cookies, "_sticker_guest")
  end

  test "verified guest cookie remains stable across requests", %{conn: conn} do
    first = get(conn, ~p"/")
    guest_user_id = get_session(first, :guest_user_id)

    second =
      first
      |> recycle()
      |> get(~p"/")

    assert get_session(second, :guest_user_id) == guest_user_id
    assert get_session(second, :local_user_id) == guest_user_id
    refute Map.has_key?(second.resp_cookies, "_sticker_guest")
  end

  test "tampered guest cookie is replaced", %{conn: conn} do
    first = get(conn, ~p"/")
    guest_user_id = get_session(first, :guest_user_id)
    signed_value = first.resp_cookies["_sticker_guest"].value

    second =
      first
      |> recycle()
      |> put_req_cookie("_sticker_guest", signed_value <> "tampered")
      |> get(~p"/")

    refute get_session(second, :guest_user_id) == guest_user_id
    assert Map.has_key?(second.resp_cookies, "_sticker_guest")
  end

  test "authenticated account identity remains local while guest identity is preserved", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> init_test_session(%{user_id: user.id, local_user_id: "attacker-selected-id"})
      |> get(~p"/")

    assert get_session(conn, :local_user_id) == user.public_id
    assert get_session(conn, :guest_user_id) =~ ~r/^gst_[A-Za-z0-9_-]{32,}$/
    refute get_session(conn, :guest_user_id) == "attacker-selected-id"
  end

  test "guest identity and allowance survive login, session renewal, and logout", %{conn: conn} do
    user = user_fixture()
    first = get(conn, ~p"/")
    guest_user_id = get_session(first, :guest_user_id)
    {:ok, _allowance} = GuestTrials.spend_credits(guest_user_id, 1)

    prediction =
      prediction_fixture(%{
        local_user_id: guest_user_id,
        credit_source: "guest",
        credit_owner_id: guest_user_id
      })

    login =
      first
      |> recycle()
      |> post(~p"/users/log-in", %{
        "user" => %{"email" => user.email, "password" => "password123"}
      })

    assert redirected_to(login, 302) == ~p"/"
    assert get_session(login, :guest_user_id) == guest_user_id
    assert get_session(login, :local_user_id) == user.public_id
    assert Predictions.get_prediction!(prediction.id).local_user_id == user.public_id

    signed_in = login |> recycle() |> get(~p"/")
    assert get_session(signed_in, :guest_user_id) == guest_user_id
    assert get_session(signed_in, :local_user_id) == user.public_id

    logout = signed_in |> recycle() |> delete(~p"/users/log-out")
    anonymous = logout |> recycle() |> get(~p"/")

    assert get_session(anonymous, :guest_user_id) == guest_user_id
    assert get_session(anonymous, :local_user_id) == guest_user_id
    assert GuestTrials.get_allowance(guest_user_id).credits_remaining == 2
  end
end
