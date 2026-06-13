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
    assert body =~ "Face sticker prompt examples"
    assert body =~ "application/ld+json"
    assert body =~ "FAQPage"
    assert body =~ "HowTo"
    assert body =~ "BreadcrumbList"

    conn = get(build_conn(), ~p"/custom-sticker-maker")
    body = html_response(conn, 200)
    assert body =~ "How do I write a custom sticker prompt?"
    assert body =~ "Custom sticker prompt templates"
    assert body =~ "/sticker-maker-online"

    conn = get(build_conn(), ~p"/cute-sticker-ideas")
    body = html_response(conn, 200)
    assert body =~ "What are easy cute sticker ideas?"
    assert body =~ "Cute sticker prompt examples"
    assert body =~ "Build a cute sticker set"

    conn = get(build_conn(), ~p"/sticker-maker-online")
    body = html_response(conn, 200)
    assert body =~ "Sticker Maker Online"
    assert body =~ "Online sticker maker workflow"
    assert body =~ "What makes a good online sticker?"

    conn = get(build_conn(), ~p"/ai-avatar-sticker")
    body = html_response(conn, 200)
    assert body =~ "AI Avatar Sticker Generator"
    assert body =~ "Avatar sticker prompt examples"

    conn = get(build_conn(), ~p"/kawaii-sticker-maker")
    body = html_response(conn, 200)
    assert body =~ "Kawaii Sticker Maker"
    assert body =~ "Kawaii sticker prompt formula"

    conn = get(build_conn(), ~p"/transparent-sticker-maker")
    body = html_response(conn, 200)
    assert body =~ "Transparent Sticker Maker"
    assert body =~ "PNG, WebP, and transparent background notes"
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
    assert body =~ "/sitemap"
    assert body =~ "<lastmod>2026-06-13</lastmod>"
    assert body =~ "<priority>1.0</priority>"
    refute body =~ "/account"
    refute body =~ "/users/log-in"
    refute body =~ "/stickers"
  end

  test "pricing page shows canceled checkout feedback", %{conn: conn} do
    conn = get(conn, ~p"/pricing?checkout=canceled")
    body = html_response(conn, 200)

    assert body =~ "Checkout canceled"
    assert body =~ "You were not charged"
  end

  test "batch download without selection redirects to history", %{conn: conn} do
    conn = get(conn, ~p"/stickers/download")

    assert redirected_to(conn, 302) == ~p"/stickers"
  end

  test "private sticker detail requires the owner session", %{conn: conn} do
    user = user_fixture()

    prediction =
      prediction_fixture(%{
        local_user_id: user.public_id,
        is_featured: nil,
        sticker_output: "https://example.com/media/prediction-private-sticker.png"
      })

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/sticker/#{prediction.id}")

    owner_conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id, local_user_id: user.public_id})

    assert {:ok, _view, html} = live(owner_conn, ~p"/sticker/#{prediction.id}")
    assert html =~ prediction.prompt
    assert html =~ "Delete"
  end

  test "private sticker download and media require the owner session", %{conn: conn} do
    user = user_fixture()

    prediction =
      prediction_fixture(%{
        local_user_id: user.public_id,
        is_featured: nil,
        sticker_output: "https://example.com/media/prediction-private-download.png"
      })

    conn = get(conn, ~p"/sticker/#{prediction.id}/download")
    assert redirected_to(conn, 302) == ~p"/"

    media =
      build_conn()
      |> get("/media/prediction-#{prediction.id}-sticker.png")

    assert response(media, 404) == "not found"
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

  test "registration requires captcha and email confirmation before free credits", %{conn: conn} do
    conn = get(conn, ~p"/users/register")
    body = html_response(conn, 200)
    assert body =~ "Captcha security check"

    captcha_answer = get_session(conn, :captcha_answer)

    conn =
      post(conn, ~p"/users/register", %{
        "captcha_answer" => captcha_answer,
        "user" => %{"email" => "new-user@example.com", "password" => "password123"}
      })

    assert redirected_to(conn, 302) == ~p"/"
    user = Sticker.Accounts.get_user_by_email("new-user@example.com")
    assert user.credits == 0
    assert is_binary(user.confirmation_token)

    {:ok, user} = Sticker.Accounts.confirm_user(user.confirmation_token)
    assert user.credits == 3
  end

  test "registration rejects wrong captcha", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{captcha_answer: "12"})
      |> post(~p"/users/register", %{
        "captcha_answer" => "13",
        "user" => %{"email" => "wrong-captcha@example.com", "password" => "password123"}
      })

    assert html_response(conn, 200) =~ "Captcha answer is incorrect"
    assert Sticker.Accounts.get_user_by_email("wrong-captcha@example.com") == nil
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
