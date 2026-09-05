defmodule StickerWeb.HistoryLiveTest do
  use StickerWeb.ConnCase

  import Sticker.AccountsFixtures
  import Sticker.PredictionsFixtures

  alias StickerWeb.HistoryLive

  test "history loads only after LiveView connects and reports shown count", %{conn: conn} do
    user = user_fixture()

    for index <- 1..25 do
      prediction_fixture(%{
        local_user_id: user.public_id,
        prompt: "history item #{index}",
        status: :succeeded
      })
    end

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id, local_user_id: user.public_id})

    static_html = get(conn, ~p"/stickers") |> html_response(200)
    assert static_html =~ ~s(id="history-initial-loading")
    refute static_html =~ "history item 1"

    {:ok, view, _html} = live(conn, ~p"/stickers")
    _html = render_async(view, 1_000)

    assert has_element?(view, "#history-count", "Showing 24 of 25")
    assert has_element?(view, "button[phx-click='load-more']", "Load More")

    view |> element("button[phx-click='load-more']") |> render_click()
    html = render_async(view, 1_000)

    assert has_element?(view, "#history-count", "Showing 25 of 25")
    assert html =~ "All stickers loaded"
    refute has_element?(view, "button[phx-click='load-more']")
  end

  test "filter replaces results after its async page resolves", %{conn: conn} do
    user = user_fixture()

    prediction_fixture(%{
      local_user_id: user.public_id,
      prompt: "completed filter result",
      status: :succeeded
    })

    prediction_fixture(%{
      local_user_id: user.public_id,
      prompt: "failed filter result",
      status: :failed
    })

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id, local_user_id: user.public_id})
    {:ok, view, _html} = live(conn, ~p"/stickers")
    _html = render_async(view, 1_000)

    view
    |> form("#history-filter", %{"status" => "failed", "query" => "", "batch_id" => "all"})
    |> render_change()

    html = render_async(view, 1_000)
    assert html =~ "failed filter result"
    refute html =~ "completed filter result"
    assert has_element?(view, "#history-count", "Showing 1 of 1")
  end

  test "history applies a favorites filter from the initial URL", %{conn: conn} do
    user = user_fixture()

    prediction_fixture(%{
      local_user_id: user.public_id,
      prompt: "saved from url",
      status: :succeeded,
      is_favorite: true
    })

    prediction_fixture(%{
      local_user_id: user.public_id,
      prompt: "not saved from url",
      status: :succeeded,
      is_favorite: false
    })

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id, local_user_id: user.public_id})
    {:ok, view, _html} = live(conn, ~p"/stickers?status=favorites")
    html = render_async(view, 1_000)

    assert html =~ "saved from url"
    refute html =~ "not saved from url"

    assert has_element?(
             view,
             "#history-filter select[name='status'] option[selected]",
             "Favorites"
           )
  end

  test "history live view is subscribed to its own PubSub updates without a refresh", %{
    conn: conn
  } do
    user = user_fixture()
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id, local_user_id: user.public_id})
    {:ok, view, _html} = live(conn, ~p"/stickers")
    _html = render_async(view, 1_000)

    prediction =
      prediction_fixture(%{
        local_user_id: user.public_id,
        prompt: "history sticker finished in the background",
        status: :succeeded
      })

    # Regression test: HistoryLive used to never subscribe to "user:<id>", so
    # completions delivered via PubSub (the real webhook/task path) never
    # reached the live view until the page was refreshed.
    Phoenix.PubSub.broadcast(
      Sticker.PubSub,
      "user:#{user.public_id}",
      {:prediction_completed, prediction}
    )

    assert render(view) =~ "history sticker finished in the background"
  end

  test "stale assign-user-id is always a no-op" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, local_user_id: "same-user"}
    }

    assert {:noreply, ^socket} =
             HistoryLive.handle_event("assign-user-id", %{"userId" => "attacker-user"}, socket)
  end

  test "stale history page results do not replace a newer request" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        history_request_ref: 22,
        history_state: :loading,
        prediction_count: 0
      }
    }

    stale_page = %{entries: [], page: 0, per_page: 24, total: 99, has_more?: true}

    assert {:noreply, returned_socket} =
             HistoryLive.handle_async({:history_page, 21}, {:ok, stale_page}, socket)

    assert returned_socket.assigns.history_request_ref == 22
    assert returned_socket.assigns.history_state == :loading
    assert returned_socket.assigns.prediction_count == 0
  end
end
