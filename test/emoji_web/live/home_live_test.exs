defmodule StickerWeb.HomeLiveTest do
  use StickerWeb.ConnCase

  import Sticker.AccountsFixtures
  import Sticker.PredictionsFixtures

  alias Sticker.Accounts
  alias Sticker.Predictions

  test "starts in text mode and switches to a dedicated portrait workflow", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ ~s(id="generator-mode-text")
    assert html =~ ~s(id="text-generator-panel")
    refute html =~ ~s(id="portrait-generator-panel")

    html = view |> element("#generator-mode-portrait") |> render_click()

    assert html =~ ~s(id="portrait-generator-panel")
    assert html =~ "Upload a clear portrait"
    assert html =~ "JPG or PNG"
    refute html =~ ~s(id="text-generator-panel")
  end

  test "does not steal focus and scroll past the hero on initial load", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    refute html =~ "phx-mounted"
    refute html =~ "focus"
  end

  test "portrait mode can be opened directly from upload links", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/?mode=portrait")

    assert html =~ ~s(id="portrait-generator-panel")
    assert html =~ ~s(name="image")
    refute html =~ ~s(id="text-generator-panel")
  end

  test "portrait selection is explicit and does not auto-upload", %{conn: conn} do
    user = user_fixture()

    conn = Plug.Test.init_test_session(conn, %{user_id: user.id, local_user_id: user.public_id})

    {:ok, view, _html} = live(conn, ~p"/")

    html = view |> element("#generator-mode-portrait") |> render_click()

    assert html =~ ~s(name="image")
    refute html =~ "data-phx-auto-upload"
    assert html =~ "Generate portrait sticker"

    before_count = Predictions.list_loading_predictions(user.public_id) |> length()

    upload =
      file_input(view, "#prediction-form", :image, [
        %{
          name: "portrait.png",
          content:
            Base.decode64!(
              "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
            ),
          type: "image/png"
        }
      ])

    html = render_upload(upload, "portrait.png")

    assert html =~ "Ready to turn into a sticker"
    assert Accounts.get_user(user.id).credits == user.credits
    assert Predictions.list_loading_predictions(user.public_id) |> length() == before_count
  end

  test "batch mode is opt-in and explains its credit behavior", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = view |> element("#batch-mode-toggle") |> render_click()

    assert html =~ ~s(aria-checked="true")
    assert html =~ "Enter up to 5 prompts, one per line"
    assert html =~ "1 credit each"
  end

  test "shows a useful moderation failure message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    send(view.pid, {:moderation_failed, "The prompt could not pass the safety check."})

    assert render(view) =~ "The prompt could not pass the safety check."
  end

  test "stale assign-user-id cannot replace the server-owned guest identity", %{
    conn: conn
  } do
    guest_user_id = "guest_server_owned"
    attacker_user_id = "guest_attacker_owned"

    prediction =
      prediction_fixture(%{
        local_user_id: guest_user_id,
        prompt: "A portrait sticker still being prepared",
        status: :starting,
        model: "face-to-sticker",
        sticker_output: nil,
        no_bg_output: nil,
        credit_source: "guest",
        credit_owner_id: guest_user_id
      })

    attacker_prediction =
      prediction_fixture(%{
        local_user_id: attacker_user_id,
        prompt: "An attacker-owned sticker",
        status: :succeeded,
        sticker_output: "https://example.com/finished-portrait.png",
        credit_source: "guest",
        credit_owner_id: attacker_user_id
      })

    conn = init_test_session(conn, %{local_user_id: guest_user_id})
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ prediction.prompt
    refute html =~ attacker_prediction.prompt

    html = render_hook(view, "assign-user-id", %{"userId" => attacker_user_id})

    assert html =~ prediction.prompt
    refute html =~ attacker_prediction.prompt
    assert html =~ "Preparing portrait"
  end

  test "canceling an active generation refunds once and rejects completion races", %{conn: conn} do
    user = user_fixture()

    active =
      prediction_fixture(%{
        local_user_id: user.public_id,
        status: :processing,
        sticker_output: nil,
        no_bg_output: nil,
        credit_source: "account",
        credit_owner_id: user.public_id,
        credit_refunded: false
      })

    completed =
      prediction_fixture(%{
        local_user_id: user.public_id,
        status: :succeeded,
        credit_source: "account",
        credit_owner_id: user.public_id,
        credit_refunded: false
      })

    credits_before = user.credits
    conn = Plug.Test.init_test_session(conn, %{user_id: user.id, local_user_id: user.public_id})
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("button[phx-click='cancel-generation'][phx-value-id='#{active.id}']")
    |> render_click()

    assert Predictions.get_prediction!(active.id).status == :canceled
    assert Accounts.get_user(user.id).credits == credits_before + 1
    assert render(view) =~ "Generation canceled"

    render_click(view, "cancel-generation", %{"id" => Integer.to_string(active.id)})
    assert Accounts.get_user(user.id).credits == credits_before + 1

    render_click(view, "cancel-generation", %{"id" => Integer.to_string(completed.id)})
    assert Predictions.get_prediction!(completed.id).status == :succeeded
    assert Accounts.get_user(user.id).credits == credits_before + 1
  end
end
