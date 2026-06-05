defmodule StickerWeb.PageControllerTest do
  use StickerWeb.ConnCase

  import Sticker.AccountsFixtures
  import Sticker.PredictionsFixtures

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "AI Sticker Maker"
  end

  test "public SEO pages render focused content", %{conn: conn} do
    conn = get(conn, ~p"/face-to-sticker")
    body = html_response(conn, 200)
    assert body =~ "Face to Sticker AI Generator"
    assert body =~ "What makes a good face to sticker upload?"

    conn = get(build_conn(), ~p"/custom-sticker-maker")
    assert html_response(conn, 200) =~ "How do I write a custom sticker prompt?"

    conn = get(build_conn(), ~p"/cute-sticker-ideas")
    assert html_response(conn, 200) =~ "What are easy cute sticker ideas?"

    conn = get(build_conn(), ~p"/sticker-maker-online")
    assert html_response(conn, 200) =~ "Sticker Maker Online"

    conn = get(build_conn(), ~p"/ai-avatar-sticker")
    assert html_response(conn, 200) =~ "AI Avatar Sticker Generator"

    conn = get(build_conn(), ~p"/kawaii-sticker-maker")
    assert html_response(conn, 200) =~ "Kawaii Sticker Maker"

    conn = get(build_conn(), ~p"/transparent-sticker-maker")
    assert html_response(conn, 200) =~ "Transparent Sticker Maker"
  end

  test "sitemap includes public SEO landing pages", %{conn: conn} do
    conn = get(conn, ~p"/sitemap.xml")
    body = response(conn, 200)

    assert body =~ "/face-to-sticker"
    assert body =~ "/custom-sticker-maker"
    assert body =~ "/cute-sticker-ideas"
    assert body =~ "/sticker-maker-online"
    assert body =~ "/ai-avatar-sticker"
    assert body =~ "/kawaii-sticker-maker"
    assert body =~ "/transparent-sticker-maker"
    refute body =~ "/account"
  end

  test "batch download without selection redirects to history", %{conn: conn} do
    conn = get(conn, ~p"/stickers/download")

    assert redirected_to(conn, 302) == ~p"/stickers"
  end

  test "checkout redirects with a friendly message when Stripe is not configured", %{conn: conn} do
    user = user_fixture()
    stripe_secret_key = System.get_env("STRIPE_SECRET_KEY")
    starter_price_id = System.get_env("STRIPE_STARTER_PRICE_ID")

    on_exit(fn ->
      restore_env("STRIPE_SECRET_KEY", stripe_secret_key)
      restore_env("STRIPE_STARTER_PRICE_ID", starter_price_id)
    end)

    System.delete_env("STRIPE_SECRET_KEY")
    System.delete_env("STRIPE_STARTER_PRICE_ID")

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id, local_user_id: user.public_id})
      |> post(~p"/checkout", %{"plan" => "starter"})

    assert redirected_to(conn, 302) == ~p"/pricing"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Checkout is not ready"
  end

  test "batch detail renders retry, cancel, and ZIP download controls", %{conn: conn} do
    user = user_fixture()

    prediction_fixture(%{
      local_user_id: user.public_id,
      batch_id: "batch-live",
      status: :succeeded,
      sticker_output: "https://example.com/sticker.webp",
      output_format: "webp"
    })

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id, local_user_id: user.public_id})

    conn = get(conn, ~p"/stickers/batches/batch-live")
    html = html_response(conn, 200)

    assert html =~ "Retry Failed"
    assert html =~ "Cancel Processing"
    assert html =~ "Download Batch ZIP"
    assert html =~ "format=original"
  end

  test "admin page renders failed generation diagnostics", %{conn: conn} do
    user = user_fixture()

    prediction_fixture(%{
      local_user_id: user.public_id,
      status: :failed,
      failure_stage: "openai",
      failure_reason: "timeout"
    })

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_req_header("authorization", basic_auth())

    {:ok, _view, html} = live(conn, ~p"/admin")

    assert html =~ "Recent Failure"
    assert html =~ "openai"
    assert html =~ "timeout"
  end

  defp basic_auth do
    username = System.fetch_env!("ADMIN_USERNAME")
    password = System.fetch_env!("ADMIN_PASSWORD")
    "Basic " <> Base.encode64("#{username}:#{password}")
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
