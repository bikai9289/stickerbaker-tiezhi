defmodule StickerWeb.PageControllerTest do
  use StickerWeb.ConnCase

  import Sticker.AccountsFixtures
  import Sticker.PredictionsFixtures

  defmodule DownloadStorageStub do
    def get_object(bucket, key) do
      {:ok,
       %{
         status_code: 200,
         body: "stored:#{bucket}/#{key}",
         headers: [{"content-type", "image/png"}]
       }}
    end
  end

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "AI Sticker Maker"
  end

  test "homepage renders a focused text generator with one generate action", %{
    conn: conn
  } do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(body)

    assert [_] = Floki.find(document, ".saas-hero-intro")
    assert [_] = Floki.find(document, ".saas-hero-copy")
    assert [_] = Floki.find(document, ".saas-hero-gallery")
    assert 4 = Floki.find(document, ".saas-hero-sticker") |> length()
    assert 4 = Floki.find(document, ".saas-hero-sticker img") |> length()
    assert [_] = Floki.find(document, "a[href=\"#generator\"].saas-hero-primary")
    assert [_] = Floki.find(document, "a[href=\"#latest\"].saas-hero-secondary")

    assert [_] = Floki.find(document, "#generator.saas-generator-workbench")
    assert [_] = Floki.find(document, "#text-generator-panel.saas-generator-panel")
    assert [_] = Floki.find(document, ".saas-text-generator")
    assert [_] = Floki.find(document, "#generator-mode-text[aria-pressed=\"true\"]")
    assert [_] = Floki.find(document, "#generator-mode-portrait[aria-pressed=\"false\"]")
    assert [] = Floki.find(document, ".saas-workbench-control-bar")
    assert [_ | _] = Floki.find(document, ".saas-workbench-trust .saas-status-chip")

    assert [generate_button] =
             Floki.find(
               document,
               "[data-analytics-event=\"text_generation_attempt\"][data-analytics-flow=\"text_to_sticker\"]"
             )

    assert Floki.text(generate_button) =~ "Generate sticker"

    assert [] = Floki.find(document, "input[type=\"file\"][name=\"image\"]")

    workbench_text =
      document
      |> Floki.find("#generator")
      |> Floki.text()

    assert workbench_text =~ "3 free guest generations left"
    assert workbench_text =~ "Describe your sticker"
    assert workbench_text =~ "Line breaks stay in one prompt unless Batch mode is on"
    refute workbench_text =~ "Bake Sticker"
    refute workbench_text =~ "Advanced defaults"
    refute workbench_text =~ "Quality: Standard"
    refute workbench_text =~ "Count:"
    refute workbench_text =~ "No Login Required"
    refute workbench_text =~ "Unlimited Generations"
    refute workbench_text =~ "AI Video"
    refute workbench_text =~ "multi-model"

    hero_text =
      document
      |> Floki.find(".saas-hero")
      |> Floki.text()

    assert hero_text =~ "3 free generations"
    assert hero_text =~ "Failed generations refund credits"
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
    assert body =~ "/photo-to-sticker"

    conn = get(build_conn(), ~p"/photo-to-sticker")
    body = html_response(conn, 200)
    assert body =~ "Photo to Sticker AI Generator"
    assert body =~ "How to turn a photo into a sticker"
    assert body =~ "Photo sticker prompt examples"
    assert body =~ "/ai-avatar-sticker"
    assert body =~ "FAQPage"
    assert body =~ "HowTo"

    conn = get(build_conn(), ~p"/custom-sticker-maker")
    body = html_response(conn, 200)
    assert body =~ "How do I write a custom sticker prompt?"
    assert body =~ "Custom sticker prompt templates"
    assert body =~ "/sticker-maker-online"
    assert body =~ "/reaction-sticker-maker"

    conn = get(build_conn(), ~p"/reaction-sticker-maker")
    body = html_response(conn, 200)
    assert body =~ "Reaction Sticker Maker"
    assert body =~ "Reaction sticker prompt examples"
    assert body =~ "Does this upload stickers to chat apps?"
    assert body =~ "/custom-sticker-maker"
    assert body =~ "FAQPage"
    assert body =~ "HowTo"

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
    assert body =~ "/anime-avatar-sticker"

    conn = get(build_conn(), ~p"/anime-avatar-sticker")
    body = html_response(conn, 200)
    assert body =~ "Anime Avatar Sticker Generator"
    assert body =~ "Anime avatar prompt examples"
    assert body =~ "Can I create anime avatar stickers from text?"
    assert body =~ "/kawaii-sticker-maker"
    assert body =~ "FAQPage"
    assert body =~ "HowTo"

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

    assert response_content_type(conn, :xml) =~ "charset=utf-8"
    assert body =~ "/face-to-sticker"
    assert body =~ "/photo-to-sticker"
    assert body =~ "/custom-sticker-maker"
    assert body =~ "/reaction-sticker-maker"
    assert body =~ "/cute-sticker-ideas"
    assert body =~ "/sticker-maker-online"
    assert body =~ "/ai-avatar-sticker"
    assert body =~ "/anime-avatar-sticker"
    assert body =~ "/kawaii-sticker-maker"
    assert body =~ "/transparent-sticker-maker"
    refute body =~ "/account"
    refute body =~ "/admin"
    refute body =~ "/users/register"
    refute body =~ "/users/log-in"
    refute body =~ "/webhooks"
    refute body =~ "/stickers/download"
  end

  test "robots references canonical sitemap", %{conn: conn} do
    conn = get(conn, ~p"/robots.txt")
    body = response(conn, 200)

    assert body =~ "Sitemap: https://ai-sticker-maker.com/sitemap.xml"
    refute Regex.match?(~r/^Disallow:\s*\//m, body)
  end

  test "core public pages render unique SEO metadata and one h1", %{conn: _conn} do
    pages = [
      {~p"/", "AI Sticker Maker - Free AI Sticker Generator Online",
       "https://ai-sticker-maker.com/"},
      {~p"/pricing", "AI Sticker Maker Pricing - Buy Sticker Credits",
       "https://ai-sticker-maker.com/pricing"},
      {~p"/search", "AI Sticker Search - Find Sticker Ideas Online",
       "https://ai-sticker-maker.com/search"},
      {~p"/face-to-sticker", "Face to Sticker AI Generator",
       "https://ai-sticker-maker.com/face-to-sticker"},
      {~p"/photo-to-sticker", "Photo to Sticker AI Generator",
       "https://ai-sticker-maker.com/photo-to-sticker"},
      {~p"/custom-sticker-maker", "Custom Sticker Maker Online",
       "https://ai-sticker-maker.com/custom-sticker-maker"},
      {~p"/reaction-sticker-maker", "Reaction Sticker Maker for Chat Stickers",
       "https://ai-sticker-maker.com/reaction-sticker-maker"},
      {~p"/sticker-maker-online", "Sticker Maker Online - Create AI Stickers",
       "https://ai-sticker-maker.com/sticker-maker-online"},
      {~p"/anime-avatar-sticker", "Anime Avatar Sticker Generator",
       "https://ai-sticker-maker.com/anime-avatar-sticker"}
    ]

    for {path, expected_title, canonical} <- pages do
      conn = get(build_conn(), path)
      body = html_response(conn, 200)
      {:ok, document} = Floki.parse_document(body)

      assert Floki.find(document, "title") |> Floki.text() == expected_title
      assert [%{"href" => ^canonical}] = meta_attrs(document, "link[rel=\"canonical\"]")
      assert [%{"content" => description}] = meta_attrs(document, "meta[name=\"description\"]")
      assert String.length(description) > 40

      assert [%{"content" => ^expected_title}] =
               meta_attrs(document, "meta[property=\"og:title\"]")

      assert [%{"content" => _}] = meta_attrs(document, "meta[property=\"og:description\"]")

      assert [%{"content" => ^expected_title}] =
               meta_attrs(document, "meta[name=\"twitter:title\"]")

      assert [%{"content" => "summary"}] = meta_attrs(document, "meta[name=\"twitter:card\"]")
      assert [%{"content" => _}] = meta_attrs(document, "meta[name=\"twitter:image\"]")
      assert meta_attrs(document, "meta[name=\"twitter:site\"]") == []
      assert meta_attrs(document, "meta[name=\"twitter:creator\"]") == []
      refute body =~ "@charliebholtz"

      assert length(Floki.find(document, "h1")) == 1
    end
  end

  test "public pages render brand trust cues", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)

    assert body =~ "Generated examples"
    assert body =~ "PNG and WebP downloads"
    assert body =~ "Failed generations refund credits"
    assert body =~ "Support and billing help"
    assert body =~ "Secure checkout"
    assert body =~ "Account-linked credits"
    assert body =~ "Refund policy available"

    conn = get(build_conn(), ~p"/pricing")
    body = html_response(conn, 200)

    assert body =~ "Credit purchase confidence"
    assert body =~ "Secure checkout"
    assert body =~ "signed-in account"
    assert body =~ "Payment and Credits"
    assert body =~ "Refund Policy"
  end

  test "status chrome is marked as non-snippet content", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(body)

    assert [%{"id" => "disconnected", "data-nosnippet" => "true"}] =
             meta_attrs(document, "#disconnected")
  end

  test "public conversion actions expose analytics hook attributes", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(body)

    assert [%{"phx-hook" => "LaunchAnalytics"}] = meta_attrs(document, "#home")
    assert [_ | _] = Floki.find(document, "[data-analytics-event=\"text_generation_attempt\"]")
    assert [_ | _] = Floki.find(document, "[data-analytics-input=\"prompt\"]")

    assert [_ | _] =
             Floki.find(
               document,
               "[data-analytics-event=\"generation_started\"][data-analytics-context=\"hero_generator_guest\"]"
             )

    assert [_ | _] = Floki.find(document, "[data-analytics-event=\"registration_cta_click\"]")
    assert [_ | _] = Floki.find(document, "[data-analytics-event=\"login_cta_click\"]")
    assert [_ | _] = Floki.find(document, "[data-analytics-event=\"pricing_cta_click\"]")

    conn = get(build_conn(), ~p"/pricing")
    body = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(body)
    assert [_ | _] = Floki.find(document, "form[data-analytics-event=\"checkout_start\"]")
    assert [_ | _] = Floki.find(document, "[data-analytics-event=\"buy_credit_cta_click\"]")
    assert [_ | _] = Floki.find(document, "[data-analytics-plan=\"starter\"]")
    assert [_ | _] = Floki.find(document, "[data-analytics-plan=\"creator\"]")

    conn = get(build_conn(), ~p"/search")
    body = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(body)
    assert [_ | _] = Floki.find(document, "[data-analytics-event=\"search_submit\"]")

    conn = get(build_conn(), ~p"/pricing")
    body = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(body)
    assert [_ | _] = Floki.find(document, "[data-analytics-page-event=\"pricing_view\"]")
    assert [_ | _] = Floki.find(document, "[data-analytics-event=\"checkout_start\"]")
    assert [_ | _] = Floki.find(document, "[data-analytics-event=\"buy_credit_cta_click\"]")

    conn = get(build_conn(), ~p"/users/log-in")
    body = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(body)
    assert [_ | _] = Floki.find(document, "form[data-analytics-event=\"login_confirm_attempt\"]")

    conn = get(build_conn(), ~p"/users/register")
    body = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(body)

    assert [_ | _] =
             Floki.find(document, "form[data-analytics-event=\"registration_confirm_attempt\"]")

    user = user_fixture()

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{user_id: user.id, local_user_id: user.public_id})
      |> get(~p"/")

    body = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(body)
    assert [_ | _] = Floki.find(document, "[data-analytics-event=\"generation_started\"]")
  end

  test "pricing page shows canceled checkout feedback", %{conn: conn} do
    conn = get(conn, ~p"/pricing?checkout=canceled")
    body = html_response(conn, 200)

    assert body =~ "Checkout canceled"
    assert body =~ "You were not charged"
  end

  test "anonymous homepage shows guest trial credits after assigning local user id", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "assign-user-id", %{"userId" => "guest_home_one"})
    html = render(view)

    assert html =~ "3 free guest generations left"
    assert html =~ "No account needed"
  end

  test "anonymous homepage shows exhausted guest trial state", %{conn: conn} do
    local_user_id = "guest_home_empty"
    {:ok, _allowance} = Sticker.GuestTrials.spend_credits(local_user_id, 3)

    conn = Plug.Test.init_test_session(conn, %{local_user_id: local_user_id})
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Free trial used"
    assert html =~ "Create an account to keep your stickers"
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
    assert html =~ ~s(data-analytics-page-event="generation_completed")
    assert html =~ ~s(data-analytics-event="download_click")
    assert html =~ ~s(data-analytics-download-type="single")
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

  test "owner can download a private sticker from internal media storage", %{conn: conn} do
    user = user_fixture()

    prediction =
      prediction_fixture(%{
        local_user_id: user.public_id,
        is_featured: nil,
        sticker_output: "https://ai-sticker-maker.com/media/prediction-private-owner-sticker.png",
        output_format: "png",
        output_content_type: "image/png"
      })

    configure_download_storage()

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id, local_user_id: user.public_id})
      |> get(~p"/sticker/#{prediction.id}/download")

    assert response(conn, 200) ==
             "stored:download-test-bucket/prediction-private-owner-sticker.png"

    assert get_resp_header(conn, "content-disposition") ==
             [~s(attachment; filename="sticker-#{prediction.id}.png")]
  end

  test "owner can batch download private stickers from internal media storage", %{conn: conn} do
    user = user_fixture()

    prediction =
      prediction_fixture(%{
        local_user_id: user.public_id,
        is_featured: nil,
        sticker_output: "https://ai-sticker-maker.com/media/prediction-private-batch.png",
        output_format: "png",
        output_content_type: "image/png"
      })

    configure_download_storage()

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id, local_user_id: user.public_id})
      |> get(~p"/stickers/download?ids=#{prediction.id}&format=original")

    assert response_content_type(conn, :zip) == "application/zip"
    assert {:ok, files} = :zip.extract(response(conn, 200), [:memory])
    expected_file_name = String.to_charlist("sticker-#{prediction.id}.png")

    assert [
             {^expected_file_name, "stored:download-test-bucket/prediction-private-batch.png"}
           ] = files
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

    conn = get(build_conn(), ~p"/users/confirm/#{user.confirmation_token}")
    assert redirected_to(conn, 302) == ~p"/?registration=confirmed"

    user = Sticker.Accounts.get_user_by_email("new-user@example.com")
    assert user.credits == 3
  end

  test "registration confirmation grants only remaining guest trial credits", %{conn: conn} do
    local_user_id = "guest_signup_one"
    {:ok, _allowance} = Sticker.GuestTrials.spend_credits(local_user_id, 2)

    conn =
      conn
      |> Plug.Test.init_test_session(%{local_user_id: local_user_id})
      |> get(~p"/users/register")

    captcha_answer = get_session(conn, :captcha_answer)

    conn =
      post(conn, ~p"/users/register", %{
        "captcha_answer" => captcha_answer,
        "user" => %{"email" => "guest-signup@example.com", "password" => "password123"}
      })

    assert redirected_to(conn, 302) == ~p"/"
    user = Sticker.Accounts.get_user_by_email("guest-signup@example.com")
    assert user.credits == 0
    assert user.signup_guest_user_id == local_user_id

    conn = get(build_conn(), ~p"/users/confirm/#{user.confirmation_token}")
    assert redirected_to(conn, 302) == ~p"/?registration=confirmed"

    user = Sticker.Accounts.get_user_by_email("guest-signup@example.com")
    assert user.credits == 1
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
    assert html =~ ~s(data-analytics-event="download_click")
    assert html =~ ~s(data-analytics-download-type="batch_zip")
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

  defp configure_download_storage do
    previous_storage = Application.get_env(:sticker, :download_storage)
    previous_bucket = System.get_env("BUCKET_NAME")

    Application.put_env(:sticker, :download_storage, DownloadStorageStub)
    System.put_env("BUCKET_NAME", "download-test-bucket")

    on_exit(fn ->
      if previous_storage do
        Application.put_env(:sticker, :download_storage, previous_storage)
      else
        Application.delete_env(:sticker, :download_storage)
      end

      restore_env("BUCKET_NAME", previous_bucket)
    end)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp meta_attrs(document, selector) do
    document
    |> Floki.find(selector)
    |> Enum.map(fn {_tag, attrs, _children} -> Map.new(attrs) end)
  end
end
