defmodule StickerWeb.AccountLiveTest do
  use StickerWeb.ConnCase

  import Sticker.AccountsFixtures
  import Sticker.PredictionsFixtures

  alias StickerWeb.AccountLive

  test "account renders section skeletons then loads each section", %{conn: conn} do
    user = user_fixture()

    recent =
      prediction_fixture(%{
        local_user_id: user.public_id,
        prompt: "recent account sticker",
        status: :succeeded
      })

    favorite =
      prediction_fixture(%{
        local_user_id: user.public_id,
        prompt: "favorite account sticker",
        status: :succeeded,
        is_favorite: true
      })

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id, local_user_id: user.public_id})

    static_html = get(conn, ~p"/account") |> html_response(200)
    assert static_html =~ ~s(id="account-summary-loading")
    assert static_html =~ ~s(id="account-recent-loading")
    assert static_html =~ ~s(id="account-favorites-loading")
    assert static_html =~ ~s(id="account-payments-loading")
    refute static_html =~ "recent account sticker"

    {:ok, view, _html} = live(conn, ~p"/account")
    html = render_async(view)

    assert html =~ ~s(id="account-summary")
    assert html =~ ~s(id="account-recent")
    assert html =~ ~s(id="account-favorites")
    assert html =~ ~s(id="account-payments")
    assert html =~ "recent account sticker"
    assert html =~ "favorite account sticker"
    assert html =~ ~s(href="/sticker/#{recent.id}")
    assert html =~ ~s(href="/sticker/#{favorite.id}")
    refute html =~ ~s(id="account-recent-loading")
  end

  test "a failed account section can retry without resetting other section states" do
    user = user_fixture()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_user: user,
        recent_state: :loading,
        favorites_state: :loaded,
        summary_state: :loaded,
        payments_state: :loaded
      }
    }

    assert {:noreply, failed_socket} =
             AccountLive.handle_async(:account_recent, {:exit, :database_unavailable}, socket)

    assert failed_socket.assigns.recent_state == :failed
    assert failed_socket.assigns.favorites_state == :loaded
    assert failed_socket.assigns.summary_state == :loaded
    assert failed_socket.assigns.payments_state == :loaded

    assert {:noreply, retrying_socket} =
             AccountLive.handle_event("retry-section", %{"section" => "recent"}, failed_socket)

    assert retrying_socket.assigns.recent_state == :loading
    assert retrying_socket.assigns.favorites_state == :loaded
    assert retrying_socket.assigns.summary_state == :loaded
    assert retrying_socket.assigns.payments_state == :loaded
  end
end
