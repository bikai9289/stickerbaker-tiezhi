defmodule StickerWeb.HomeLiveTest do
  use StickerWeb.ConnCase

  import Sticker.AccountsFixtures
  import Sticker.PredictionsFixtures

  alias Sticker.Accounts
  alias Sticker.GuestAbuse
  alias Sticker.GuestAbuse.Attempt
  alias Sticker.GuestTrials
  alias Sticker.Predictions
  alias Sticker.Repo

  defmodule GenerationProviderStub do
    def moderate(_prompt, _user_id, _prediction_id), do: :ok
    def gen_face_to_sticker(_prompt, _image_uri, _user_id, _prediction_id), do: :ok
  end

  defmodule TurnstileVerifierStub do
    @behaviour Sticker.Turnstile.Verifier

    @impl true
    def verify(token, remote_ip, request_id) do
      send(Application.fetch_env!(:sticker, :home_live_test_pid), {:verified, token, remote_ip, request_id})
      Application.get_env(:sticker, :home_live_verifier_result, :ok)
    end
  end

  defmodule SourceImageStorageStub do
    def save_r2_upload(file_name, _bytes, content_type) do
      send(Application.fetch_env!(:sticker, :home_live_test_pid), {:source_saved, file_name, content_type})
      "https://storage.example/#{file_name}"
    end
  end

  setup do
    previous_provider = Application.get_env(:sticker, :generation_provider)
    previous_turnstile = Application.get_env(:sticker, :turnstile)
    previous_verifier = Application.get_env(:sticker, :turnstile_verifier)
    previous_storage = Application.get_env(:sticker, :source_image_storage)
    previous_pid = Application.get_env(:sticker, :home_live_test_pid)

    Application.put_env(:sticker, :generation_provider, GenerationProviderStub)
    Application.put_env(:sticker, :turnstile, enabled: false)
    Application.put_env(:sticker, :turnstile_verifier, TurnstileVerifierStub)
    Application.put_env(:sticker, :source_image_storage, SourceImageStorageStub)
    Application.put_env(:sticker, :home_live_test_pid, self())

    on_exit(fn ->
      restore_env(:generation_provider, previous_provider)
      restore_env(:turnstile, previous_turnstile)
      restore_env(:turnstile_verifier, previous_verifier)
      restore_env(:source_image_storage, previous_storage)
      restore_env(:home_live_test_pid, previous_pid)
      Application.delete_env(:sticker, :home_live_verifier_result)
    end)

    :ok
  end

  test "first low-risk guest text request reserves one task and spends one credit", %{conn: conn} do
    conn = get(conn, ~p"/")
    guest_user_id = get_session(conn, :guest_user_id)
    {:ok, view, _html} = live(recycle(conn), ~p"/")

    html = view |> form("#prediction-form", %{"prompt" => "a cat"}) |> render_submit()

    assert html =~ "Sticker generation started"
    assert GuestTrials.get_allowance(guest_user_id).credits_remaining == 2
    assert Repo.aggregate(Attempt, :count) == 1
    assert [%{prompt: "a cat"}] = Predictions.list_user_recent_predictions(guest_user_id, 12)
  end

  test "repeat guest must complete Turnstile before text generation", %{conn: conn} do
    Application.put_env(:sticker, :turnstile,
      enabled: true,
      site_key: "site-key",
      secret_key: "secret-key"
    )

    guest_user_id = "gst_repeat_home_guest"
    {:ok, _allowance} = GuestTrials.spend_credits(guest_user_id, 1)
    conn = init_test_session(conn, %{local_user_id: guest_user_id})
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ ~s(id="guest-turnstile")
    assert html =~ "Complete the security check to continue."

    view |> form("#prediction-form", %{"prompt" => "a protected cat"}) |> render_submit()
    assert GuestTrials.get_allowance(guest_user_id).credits_remaining == 2
    assert Repo.aggregate(Attempt, :count) == 0

    render_hook(view, "turnstile-token", %{"token" => "valid-token"})
    html = view |> form("#prediction-form", %{"prompt" => "a protected cat"}) |> render_submit()

    assert html =~ "Sticker generation started"
    assert GuestTrials.get_allowance(guest_user_id).credits_remaining == 1
    assert Repo.aggregate(Attempt, :count) == 1
    assert_receive {:verified, "valid-token", _remote_ip, _request_id}

    render_hook(view, "turnstile-token", %{"token" => "second-valid-token"})
    html = view |> form("#prediction-form", %{"prompt" => "a final cat"}) |> render_submit()

    assert GuestTrials.get_allowance(guest_user_id).credits_remaining == 0
    refute html =~ ~s(id="guest-turnstile")
    assert html =~ "Free trial used"
  end

  test "batch request reserves and spends the parsed prompt count", %{conn: conn} do
    conn = get(conn, ~p"/")
    guest_user_id = get_session(conn, :guest_user_id)
    {:ok, view, _html} = live(recycle(conn), ~p"/")
    view |> element("#batch-mode-toggle") |> render_click()

    view
    |> form("#prediction-form", %{"prompt" => "a cat\na dog"})
    |> render_submit()

    assert GuestTrials.get_allowance(guest_user_id).credits_remaining == 1
    assert %Attempt{task_count: 2} = Repo.one!(Attempt)
  end

  test "network limit blocks a guest without spending credit", %{conn: conn} do
    ip_hash = GuestAbuse.ip_hash("127.0.0.1")
    reserve_attempt(ip_hash, "gst_prior_one", 5)
    reserve_attempt(ip_hash, "gst_prior_two", 1)

    conn = get(conn, ~p"/")
    guest_user_id = get_session(conn, :guest_user_id)
    {:ok, view, _html} = live(recycle(conn), ~p"/")

    html = view |> form("#prediction-form", %{"prompt" => "a blocked cat"}) |> render_submit()

    assert html =~ "This network has reached its free generation limit"
    assert GuestTrials.get_allowance(guest_user_id).credits_remaining == 3
    assert Repo.aggregate(Attempt, :count) == 2
  end

  test "authenticated generation bypasses the guest ledger", %{conn: conn} do
    user = user_fixture()
    conn = init_test_session(conn, %{user_id: user.id, local_user_id: user.public_id})
    {:ok, view, _html} = live(conn, ~p"/")

    view |> form("#prediction-form", %{"prompt" => "an account cat"}) |> render_submit()

    assert Repo.aggregate(Attempt, :count) == 0
    assert Accounts.get_user(user.id).credits == user.credits - 1
  end

  test "portrait challenge is required before consuming the selected upload", %{conn: conn} do
    Application.put_env(:sticker, :turnstile,
      enabled: true,
      site_key: "site-key",
      secret_key: "secret-key"
    )

    guest_user_id = "gst_portrait_repeat"
    {:ok, _allowance} = GuestTrials.spend_credits(guest_user_id, 1)
    conn = init_test_session(conn, %{local_user_id: guest_user_id})
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#generator-mode-portrait") |> render_click()

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

    render_upload(upload, "portrait.png")
    html = view |> form("#prediction-form", %{"prompt" => ""}) |> render_submit()

    assert html =~ "Complete the security check to continue."
    assert html =~ "Ready to turn into a sticker"
    assert GuestTrials.get_allowance(guest_user_id).credits_remaining == 2
    assert Repo.aggregate(Attempt, :count) == 0
  end

  test "verified portrait request reserves one task before spending credit", %{conn: conn} do
    Application.put_env(:sticker, :turnstile,
      enabled: true,
      site_key: "site-key",
      secret_key: "secret-key"
    )

    guest_user_id = "gst_portrait_verified"
    {:ok, _allowance} = GuestTrials.spend_credits(guest_user_id, 1)
    conn = init_test_session(conn, %{local_user_id: guest_user_id})
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#generator-mode-portrait") |> render_click()

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

    render_upload(upload, "portrait.png")
    render_hook(view, "turnstile-token", %{"token" => "valid-token"})
    html = view |> form("#prediction-form", %{"prompt" => "kawaii"}) |> render_submit()

    assert html =~ "Face sticker generation started"
    assert GuestTrials.get_allowance(guest_user_id).credits_remaining == 1
    assert %Attempt{mode: "portrait", task_count: 1, turnstile_verified: true} = Repo.one!(Attempt)
    assert [%{model: "face-to-sticker"}] = Predictions.list_user_recent_predictions(guest_user_id, 12)
    assert_receive {:source_saved, _file_name, "image/png"}
  end

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

  test "guest homepage live view is subscribed to its own PubSub updates without a refresh", %{
    conn: conn
  } do
    conn = get(conn, ~p"/")
    guest_user_id = get_session(conn, :guest_user_id)
    {:ok, view, _html} = live(recycle(conn), ~p"/")

    prediction =
      prediction_fixture(%{
        local_user_id: guest_user_id,
        prompt: "A sticker finished in the background",
        status: :succeeded,
        sticker_output: "https://example.com/background-finished.png",
        credit_source: "guest",
        credit_owner_id: guest_user_id
      })

    # This mirrors how the real webhook/task pipeline delivers completion: a
    # PubSub broadcast to "user:<id>", not a direct message to the view pid.
    # Regression test for a bug where HomeLive never subscribed to this topic,
    # so guests only saw finished stickers after manually refreshing the page.
    Phoenix.PubSub.broadcast(
      Sticker.PubSub,
      "user:#{guest_user_id}",
      {:prediction_completed, prediction}
    )

    assert render(view) =~ "A sticker finished in the background"
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

  defp restore_env(key, nil), do: Application.delete_env(:sticker, key)
  defp restore_env(key, value), do: Application.put_env(:sticker, key, value)

  defp reserve_attempt(ip_hash, guest_user_id, task_count) do
    attrs = %{
      request_id: Ecto.UUID.generate(),
      guest_user_id: guest_user_id,
      ip_hash: ip_hash,
      mode: "text",
      task_count: task_count,
      turnstile_required: false,
      turnstile_verified: false,
      risk_reason: nil
    }

    assert {:ok, %Attempt{}} = GuestAbuse.reserve_attempt(attrs)
  end
end
