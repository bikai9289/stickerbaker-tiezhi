defmodule StickerWeb.HomeAuthIntentTest do
  use StickerWeb.ConnCase

  import Sticker.AccountsFixtures

  alias Sticker.Accounts
  alias Sticker.Predictions

  @valid_prompt "cute panda eating cookie"
  @long_prompt String.duplicate("sticker ", 180)

  test "anonymous text submit stores pending prompt and redirects to registration", %{conn: conn} do
    conn = post(conn, ~p"/users/pending-prompt", %{"prompt" => @valid_prompt})

    assert redirected_to(conn, 302) == ~p"/users/register"
    assert get_session(conn, :pending_prompt) == @valid_prompt
    assert get_session(conn, :pending_prompt_source) == "home_generator"
    assert is_integer(get_session(conn, :pending_prompt_created_at))
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Create an account"
  end

  test "anonymous empty prompt stays on homepage and does not store pending prompt", %{conn: conn} do
    conn = post(conn, ~p"/users/pending-prompt", %{"prompt" => "   "})

    assert redirected_to(conn, 302) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Add at least one sticker prompt."
    refute get_session(conn, :pending_prompt)
  end

  test "anonymous oversized prompt stays on homepage and does not store pending prompt", %{conn: conn} do
    conn = post(conn, ~p"/users/pending-prompt", %{"prompt" => @long_prompt})

    assert redirected_to(conn, 302) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Prompt is too long"
    refute get_session(conn, :pending_prompt)
  end

  test "anonymous multi-line prompt is bounded before registration redirect", %{conn: conn} do
    prompt = Enum.map_join(1..7, "\n", &"sticker prompt #{&1}")

    conn = post(conn, ~p"/users/pending-prompt", %{"prompt" => prompt})

    assert redirected_to(conn, 302) == ~p"/users/register"

    assert get_session(conn, :pending_prompt) ==
             Enum.map_join(1..5, "\n", &"sticker prompt #{&1}")
  end

  test "registration success restores pending prompt and clears pending session", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{
        pending_prompt: @valid_prompt,
        pending_prompt_source: "home_generator",
        pending_prompt_created_at: System.system_time(:second),
        captcha_answer: "7"
      })
      |> post(~p"/users/register", %{
        "captcha_answer" => "7",
        "user" => %{"email" => "prompt-register@example.com", "password" => "password123"}
      })

    assert redirected_to(conn, 302) == "/?prompt=cute+panda+eating+cookie#generator"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your prompt is ready"
    refute get_session(conn, :pending_prompt)
    refute get_session(conn, :pending_prompt_source)
    refute get_session(conn, :pending_prompt_created_at)
  end

  test "login success restores pending prompt and clears pending session", %{conn: conn} do
    user = user_fixture(%{email: "prompt-login@example.com", password: "password123"})

    conn =
      conn
      |> Plug.Test.init_test_session(%{
        pending_prompt: @valid_prompt,
        pending_prompt_source: "home_generator",
        pending_prompt_created_at: System.system_time(:second)
      })
      |> post(~p"/users/log-in", %{
        "user" => %{"email" => user.email, "password" => "password123"}
      })

    assert redirected_to(conn, 302) == "/?prompt=cute+panda+eating+cookie#generator"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your prompt is ready"
    refute get_session(conn, :pending_prompt)
  end

  test "restored prompt prefills homepage without creating prediction or spending credits", %{conn: conn} do
    user = user_fixture()

    before_count = Predictions.list_loading_predictions(user.public_id) |> length()

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id, local_user_id: user.public_id})
      |> get(~p"/?prompt=#{@valid_prompt}")

    html = html_response(conn, 200)
    assert html =~ @valid_prompt
    assert html =~ "hero_generator_restored_prompt"

    user_after = Accounts.get_user(user.id)
    assert user_after.credits == user.credits
    assert Predictions.list_loading_predictions(user.public_id) |> length() == before_count
  end

  test "registration page tracks pending prompt source", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{
        pending_prompt: @valid_prompt,
        pending_prompt_source: "home_generator",
        pending_prompt_created_at: System.system_time(:second)
      })
      |> get(~p"/users/register")

    assert html_response(conn, 200) =~ "registration_from_prompt"
  end

  test "direct registration without pending prompt keeps existing redirect behavior", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{captcha_answer: "9"})
      |> post(~p"/users/register", %{
        "captcha_answer" => "9",
        "user" => %{"email" => "direct-register@example.com", "password" => "password123"}
      })

    assert redirected_to(conn, 302) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Signed in successfully"
  end

  test "direct login without pending prompt keeps existing redirect behavior", %{conn: conn} do
    user = user_fixture(%{email: "direct-login@example.com", password: "password123"})

    conn =
      post(conn, ~p"/users/log-in", %{
        "user" => %{"email" => user.email, "password" => "password123"}
      })

    assert redirected_to(conn, 302) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Signed in successfully"
  end

  test "anonymous face upload area links to registration instead of file input", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(html)

    assert [_ | _] = Floki.find(document, "[data-analytics-context=\"home_upload_auth_gate\"]")
    assert Floki.find(document, "input[type=\"file\"][name=\"image\"]") == []
  end

  test "authenticated face upload area keeps file input", %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id, local_user_id: user.public_id})
      |> get(~p"/")

    html = html_response(conn, 200)
    {:ok, document} = Floki.parse_document(html)

    assert [_ | _] = Floki.find(document, "input[type=\"file\"][name=\"image\"]")
  end
end
