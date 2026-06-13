# Payment Flow Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make credit purchases safe for real users by recording checkout attempts before redirect, validating Stripe webhook data before crediting, surfacing payment/refund states in user and admin UI, and handling full refunds without unsafe partial-refund automation.

**Architecture:** Keep `Sticker.Payments` as the payment boundary and keep controllers thin. Add a separate `payment_attempts` table for the checkout lifecycle, keep `payment_events` as the crediting/refund ledger, and add a `payment_webhook_events` table for webhook idempotency. First release policy: only full refunds automatically remove credits; partial refunds and low-balance refunds become review records.

**Tech Stack:** Elixir, Phoenix 1.7, Ecto, ExUnit, PostgreSQL-compatible Ecto migrations, Req for Stripe Checkout API calls.

---

## Product Decisions

- Stripe Checkout is the production provider for credit purchases.
- A checkout attempt is created before redirecting the user to Stripe.
- Credits are added only after a verified `checkout.session.completed` webhook with `payment_status == "paid"`.
- The webhook handler must validate plan, price ID, amount, currency, user, and session ID before crediting.
- Full refunds automatically remove the original credits when the user still has enough credits.
- Partial refunds are not automatically converted into credits. They are marked `partial_refund_review`.
- Refunds where the user has already spent too many credits are marked `review_required`.
- Users see simple, non-technical statuses. Admins see raw Stripe IDs and review flags.

## User-Facing Payment States

| Internal state | User-facing message |
| --- | --- |
| `created` | Checkout started. Complete payment securely with Stripe. |
| `open` | Checkout is open. Complete payment securely with Stripe. |
| `completed` + no payment event yet | Payment received. Credits are being added. |
| `credited` | Paid. Credits added. |
| `canceled` | Checkout canceled. You were not charged. |
| `expired` | Checkout expired. You were not charged. |
| `failed` | Payment was not completed. No credits were added. |
| `refunded` | Refunded. Credits removed. |
| `review_required` | Refund is under review. Contact support if you need help. |
| `partial_refund_review` | Partial refund is under review. Contact support if you need help. |

## File Structure

- Create `priv/repo/migrations/20260613130000_create_payment_attempts.exs`: pending checkout lifecycle table.
- Create `priv/repo/migrations/20260613130500_create_payment_webhook_events.exs`: Stripe webhook idempotency table.
- Modify `priv/repo/migrations` only by adding new migrations; do not rewrite previous migrations.
- Create `lib/sticker/payments/payment_attempt.ex`: Ecto schema and changesets for checkout state.
- Create `lib/sticker/payments/payment_webhook_event.ex`: Ecto schema and changesets for webhook event records.
- Modify `lib/sticker/payments/payment_event.ex`: add amount/price/refund statuses needed by the payment ledger.
- Modify `lib/sticker/payments.ex`: create attempts before Stripe redirect, validate webhook sessions, record webhook events, credit once, and safely classify refunds.
- Modify `lib/sticker_web/controllers/checkout_controller.ex`: use the updated create-checkout return value and keep friendly failures.
- Modify `lib/sticker_web/controllers/stripe_webhook_controller.ex`: dispatch only supported events and keep bad signatures at HTTP 400.
- Modify `lib/sticker_web/controllers/page_controller.ex` and `lib/sticker_web/controllers/page_html/pricing.html.heex`: show canceled/expired/failed feedback on Pricing.
- Modify `lib/sticker_web/live/account_live.ex` and `lib/sticker_web/live/account_live.html.heex`: show attempt and ledger states.
- Modify `lib/sticker_web/live/admin_payments_live.ex` and `lib/sticker_web/live/admin_payments_live.html.heex`: show review-required and partial-refund records.
- Modify `test/emoji/payments_test.exs`: payment domain tests.
- Modify `test/emoji_web/controllers/stripe_webhook_controller_test.exs`: webhook tests.
- Modify `test/emoji_web/controllers/page_controller_test.exs`: checkout/pricing feedback tests.
- Modify `README.md`: document the stricter payment flow, webhook events, and live key rotation rule.

---

### Task 1: Add Checkout Attempt Storage

**Files:**
- Create: `priv/repo/migrations/20260613130000_create_payment_attempts.exs`
- Create: `lib/sticker/payments/payment_attempt.ex`
- Modify: `lib/sticker/payments.ex`
- Test: `test/emoji/payments_test.exs`

- [ ] **Step 1: Write failing tests for attempt creation**

Add these tests near the top of `test/emoji/payments_test.exs`, after aliases:

```elixir
  alias Sticker.Payments.PaymentAttempt
```

Add tests before existing fulfillment tests:

```elixir
  test "create_payment_attempt/2 records pending Stripe checkout details" do
    user = user_fixture()
    plan = Payments.get_plan("starter")

    assert {:ok, attempt} = Payments.create_payment_attempt(plan, user)

    assert attempt.provider == "stripe"
    assert attempt.user_id == user.id
    assert attempt.plan == "starter"
    assert attempt.credits == 50
    assert attempt.amount == 499
    assert attempt.currency == "usd"
    assert attempt.status == "created"
    assert attempt.stripe_price_id == System.get_env("STRIPE_STARTER_PRICE_ID")
  end

  test "mark_payment_attempt_open/2 stores Stripe session details" do
    user = user_fixture()
    plan = Payments.get_plan("starter")
    {:ok, attempt} = Payments.create_payment_attempt(plan, user)

    assert {:ok, updated} =
             Payments.mark_payment_attempt_open(attempt, %{
               "id" => "cs_test_attempt",
               "payment_intent" => "pi_test_attempt",
               "url" => "https://checkout.stripe.com/c/pay/cs_test_attempt"
             })

    assert updated.status == "open"
    assert updated.stripe_session_id == "cs_test_attempt"
    assert updated.provider_order_id == "pi_test_attempt"
    assert updated.checkout_url == "https://checkout.stripe.com/c/pay/cs_test_attempt"
  end
```

Add this `setup` block after the `import Sticker.AccountsFixtures` line. Keep the existing `restore_env/2` helpers at the bottom of the file:

```elixir
  setup do
    old_starter = System.get_env("STRIPE_STARTER_PRICE_ID")
    old_creator = System.get_env("STRIPE_CREATOR_PRICE_ID")

    System.put_env("STRIPE_STARTER_PRICE_ID", "price_starter_test")
    System.put_env("STRIPE_CREATOR_PRICE_ID", "price_creator_test")

    on_exit(fn ->
      restore_env("STRIPE_STARTER_PRICE_ID", old_starter)
      restore_env("STRIPE_CREATOR_PRICE_ID", old_creator)
    end)

    :ok
  end
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: compilation fails because `Sticker.Payments.PaymentAttempt`, `Payments.create_payment_attempt/2`, and `Payments.mark_payment_attempt_open/2` do not exist.

- [ ] **Step 3: Add payment attempts migration**

Create `priv/repo/migrations/20260613130000_create_payment_attempts.exs`:

```elixir
defmodule Sticker.Repo.Migrations.CreatePaymentAttempts do
  use Ecto.Migration

  def change do
    create table(:payment_attempts) do
      add :provider, :string, null: false, default: "stripe"
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :plan, :string, null: false
      add :credits, :integer, null: false
      add :amount, :integer, null: false
      add :currency, :string, null: false
      add :status, :string, null: false, default: "created"
      add :stripe_price_id, :string, null: false
      add :stripe_session_id, :string
      add :provider_order_id, :string
      add :checkout_url, :text
      add :failure_reason, :text

      timestamps()
    end

    create index(:payment_attempts, [:user_id])
    create index(:payment_attempts, [:status])
    create unique_index(:payment_attempts, [:stripe_session_id])
  end
end
```

- [ ] **Step 4: Add payment attempt schema**

Create `lib/sticker/payments/payment_attempt.ex`:

```elixir
defmodule Sticker.Payments.PaymentAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ["created", "open", "completed", "credited", "canceled", "expired", "failed"]

  schema "payment_attempts" do
    field :provider, :string, default: "stripe"
    field :user_id, :integer
    field :plan, :string
    field :credits, :integer
    field :amount, :integer
    field :currency, :string
    field :status, :string, default: "created"
    field :stripe_price_id, :string
    field :stripe_session_id, :string
    field :provider_order_id, :string
    field :checkout_url, :string
    field :failure_reason, :string

    timestamps()
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :provider,
      :user_id,
      :plan,
      :credits,
      :amount,
      :currency,
      :status,
      :stripe_price_id,
      :stripe_session_id,
      :provider_order_id,
      :checkout_url,
      :failure_reason
    ])
    |> validate_required([:provider, :user_id, :plan, :credits, :amount, :currency, :status, :stripe_price_id])
    |> validate_inclusion(:provider, ["stripe"])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:credits, greater_than: 0)
    |> validate_number(:amount, greater_than: 0)
    |> unique_constraint(:stripe_session_id)
  end
end
```

- [ ] **Step 5: Add attempt functions to Payments**

In `lib/sticker/payments.ex`, add the alias:

```elixir
  alias Sticker.Payments.PaymentAttempt
```

Update the plan maps in `plans/0`:

```elixir
      %{
        id: "starter",
        name: "Starter",
        price: "$4.99",
        amount: 499,
        currency: "usd",
        credits: 50,
        env: "STRIPE_STARTER_PRICE_ID"
      },
      %{
        id: "creator",
        name: "Creator",
        price: "$9.99",
        amount: 999,
        currency: "usd",
        credits: 150,
        env: "STRIPE_CREATOR_PRICE_ID"
      }
```

Add these public functions near `get_plan/1`:

```elixir
  def create_payment_attempt(plan, user) do
    with {:ok, price_id} <- fetch_price_id(plan) do
      %PaymentAttempt{}
      |> PaymentAttempt.changeset(%{
        provider: "stripe",
        user_id: user.id,
        plan: plan.id,
        credits: plan.credits,
        amount: plan.amount,
        currency: plan.currency,
        status: "created",
        stripe_price_id: price_id
      })
      |> Repo.insert()
    end
  end

  def mark_payment_attempt_open(%PaymentAttempt{} = attempt, session) do
    attempt
    |> PaymentAttempt.changeset(%{
      status: "open",
      stripe_session_id: session["id"],
      provider_order_id: session["payment_intent"],
      checkout_url: session["url"]
    })
    |> Repo.update()
  end
```

- [ ] **Step 6: Run migration and tests**

Run:

```bash
mix ecto.migrate
mix test test/emoji/payments_test.exs
```

Expected: the new attempt tests pass. Existing tests may still pass unchanged.

- [ ] **Step 7: Commit Task 1**

Run:

```bash
git add priv/repo/migrations/20260613130000_create_payment_attempts.exs lib/sticker/payments/payment_attempt.ex lib/sticker/payments.ex test/emoji/payments_test.exs
git commit -m "Add payment attempt lifecycle storage"
```

---

### Task 2: Create Stripe Checkout Through Attempts

**Files:**
- Modify: `lib/sticker/payments.ex`
- Test: `test/emoji/payments_test.exs`

- [ ] **Step 1: Write failing unit test for checkout attempt integration**

Add this test to `test/emoji/payments_test.exs`. It uses a tiny TCP HTTP stub instead of adding a test dependency:

```elixir
  test "create_stripe_checkout_session/4 creates an attempt before returning checkout URL" do
    user = user_fixture()
    plan = Payments.get_plan("starter")

    {:ok, url, get_request} =
      start_stripe_checkout_stub(%{
        "id" => "cs_test_create",
        "payment_intent" => "pi_test_create",
        "url" => "https://checkout.stripe.com/c/pay/cs_test_create"
      })

    old_api = System.get_env("STRIPE_API_BASE")
    System.put_env("STRIPE_API_BASE", url)

    on_exit(fn -> restore_env("STRIPE_API_BASE", old_api) end)

    old_key = System.get_env("STRIPE_SECRET_KEY")
    System.put_env("STRIPE_SECRET_KEY", "sk_test_checkout")
    on_exit(fn -> restore_env("STRIPE_SECRET_KEY", old_key) end)

    assert {:ok, "https://checkout.stripe.com/c/pay/cs_test_create"} =
             Payments.create_stripe_checkout_session(
               plan,
               user,
               "https://example.com/account?checkout=success",
               "https://example.com/pricing?checkout=canceled"
             )

    request = get_request.()
    assert request =~ "POST /v1/checkout/sessions"
    assert String.downcase(request) =~ "authorization: bearer sk_test_checkout"
    assert request =~ "metadata%5Bpayment_attempt_id%5D="
    assert request =~ "line_items%5B0%5D%5Bprice%5D=price_starter_test"

    attempt = Repo.get_by!(PaymentAttempt, stripe_session_id: "cs_test_create")
    assert attempt.status == "open"
    assert attempt.provider_order_id == "pi_test_create"
  end
```

Add these helpers near the bottom of `test/emoji/payments_test.exs`, before `restore_env/2`:

```elixir
  defp start_stripe_checkout_stub(response_body) do
    parent = self()
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])
    {:ok, port} = :inet.port(listen_socket)

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen_socket)
      {:ok, request} = read_http_request(socket, "")
      send(parent, {:stripe_checkout_request, request})

      body = Jason.encode!(response_body)

      :ok =
        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\n",
          "content-type: application/json\r\n",
          "content-length: #{byte_size(body)}\r\n",
          "connection: close\r\n",
          "\r\n",
          body
        ])

      :gen_tcp.close(socket)
      :gen_tcp.close(listen_socket)
    end)

    get_request = fn ->
      assert_receive {:stripe_checkout_request, request}, 2_000
      request
    end

    {:ok, "http://127.0.0.1:#{port}/v1", get_request}
  end

  defp read_http_request(socket, acc) do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, chunk} ->
        request = acc <> chunk

        if complete_http_request?(request) do
          {:ok, request}
        else
          read_http_request(socket, request)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp complete_http_request?(request) do
    case String.split(request, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        case Regex.run(~r/content-length:\s*(\d+)/i, headers) do
          [_match, length] -> byte_size(body) >= String.to_integer(length)
          nil -> true
        end

      _parts ->
        false
    end
  end
```

- [ ] **Step 2: Run test to verify RED**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: the new test fails because `STRIPE_API_BASE` is ignored and `metadata[payment_attempt_id]` is not sent.

- [ ] **Step 3: Make Stripe API base configurable for tests**

In `lib/sticker/payments.ex`, replace direct use of `@stripe_api` in `Req.post` with:

```elixir
      case Req.post(url: "#{stripe_api_base()}/checkout/sessions", form: body, headers: headers) do
```

Add helper near `payment_provider/0`:

```elixir
  defp stripe_api_base do
    System.get_env("STRIPE_API_BASE", @stripe_api)
  end
```

- [ ] **Step 4: Add attempt ID to Checkout metadata**

Replace `create_stripe_checkout_session/4` with:

```elixir
  def create_stripe_checkout_session(plan, user, success_url, cancel_url) do
    with {:ok, price_id} <- fetch_price_id(plan),
         {:ok, attempt} <- create_payment_attempt(plan, user),
         {:ok, headers} <- headers() do
      body = [
        {"mode", "payment"},
        {"line_items[0][price]", price_id},
        {"line_items[0][quantity]", "1"},
        {"success_url", success_url},
        {"cancel_url", cancel_url},
        {"customer_email", user.email},
        {"metadata[user_id]", Integer.to_string(user.id)},
        {"metadata[credits]", Integer.to_string(plan.credits)},
        {"metadata[plan]", plan.id},
        {"metadata[payment_attempt_id]", Integer.to_string(attempt.id)},
        {"client_reference_id", Integer.to_string(user.id)}
      ]

      case Req.post(url: "#{stripe_api_base()}/checkout/sessions", form: body, headers: headers) do
        {:ok, %{status: status, body: %{"url" => url} = session}} when status in 200..299 ->
          case mark_payment_attempt_open(attempt, session) do
            {:ok, _attempt} -> {:ok, url}
            {:error, reason} -> {:error, reason}
          end

        {:ok, %{status: status, body: body}} ->
          mark_payment_attempt_failed(attempt, "stripe_error:#{status}")
          {:error, {:stripe_error, status, body}}

        {:error, reason} ->
          mark_payment_attempt_failed(attempt, inspect(reason))
          {:error, reason}
      end
    end
  end
```

Add helper:

```elixir
  def mark_payment_attempt_failed(%PaymentAttempt{} = attempt, reason) do
    attempt
    |> PaymentAttempt.changeset(%{status: "failed", failure_reason: to_string(reason)})
    |> Repo.update()
  end
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
mix test test/emoji/payments_test.exs test/emoji_web/controllers/page_controller_test.exs
```

Expected: tests pass with the in-test TCP HTTP stub handling the local Stripe API call.

- [ ] **Step 6: Commit Task 2**

Run:

```bash
git add lib/sticker/payments.ex test/emoji/payments_test.exs
git commit -m "Create Stripe checkout sessions from payment attempts"
```

---

### Task 3: Record Webhook Events and Enforce Signature Timestamp Tolerance

**Files:**
- Create: `priv/repo/migrations/20260613130500_create_payment_webhook_events.exs`
- Create: `lib/sticker/payments/payment_webhook_event.ex`
- Modify: `lib/sticker/payments.ex`
- Test: `test/emoji/payments_test.exs`

- [ ] **Step 1: Write failing tests**

Add alias:

```elixir
  alias Sticker.Payments.PaymentWebhookEvent
```

Add tests:

```elixir
  test "record_webhook_event/1 stores Stripe event ids once" do
    assert {:ok, event} =
             Payments.record_webhook_event(%{
               "id" => "evt_once",
               "type" => "checkout.session.completed",
               "livemode" => false
             })

    assert event.stripe_event_id == "evt_once"
    assert event.event_type == "checkout.session.completed"
    assert event.status == "received"

    assert {:error, :duplicate_event} =
             Payments.record_webhook_event(%{
               "id" => "evt_once",
               "type" => "checkout.session.completed",
               "livemode" => false
             })
  end

  test "verify_webhook/2 rejects stale Stripe signatures" do
    secret = System.get_env("STRIPE_WEBHOOK_SECRET")
    System.put_env("STRIPE_WEBHOOK_SECRET", "whsec_stripe_test")

    on_exit(fn -> restore_env("STRIPE_WEBHOOK_SECRET", secret) end)

    payload = ~s({"type":"checkout.session.completed"})
    timestamp = "1710000000"

    digest =
      :crypto.mac(:hmac, :sha256, "whsec_stripe_test", "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    assert {:error, :invalid_signature} =
             Payments.verify_webhook(payload, "t=#{timestamp},v1=#{digest}")
  end
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: compilation fails for `PaymentWebhookEvent` and `record_webhook_event/1`; stale signature test fails because current code accepts old timestamps.

- [ ] **Step 3: Add webhook event migration**

Create `priv/repo/migrations/20260613130500_create_payment_webhook_events.exs`:

```elixir
defmodule Sticker.Repo.Migrations.CreatePaymentWebhookEvents do
  use Ecto.Migration

  def change do
    create table(:payment_webhook_events) do
      add :provider, :string, null: false, default: "stripe"
      add :stripe_event_id, :string, null: false
      add :event_type, :string, null: false
      add :livemode, :boolean, null: false, default: false
      add :status, :string, null: false, default: "received"
      add :error_reason, :text

      timestamps()
    end

    create unique_index(:payment_webhook_events, [:provider, :stripe_event_id])
    create index(:payment_webhook_events, [:event_type])
    create index(:payment_webhook_events, [:status])
  end
end
```

- [ ] **Step 4: Add webhook event schema**

Create `lib/sticker/payments/payment_webhook_event.ex`:

```elixir
defmodule Sticker.Payments.PaymentWebhookEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payment_webhook_events" do
    field :provider, :string, default: "stripe"
    field :stripe_event_id, :string
    field :event_type, :string
    field :livemode, :boolean, default: false
    field :status, :string, default: "received"
    field :error_reason, :string

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:provider, :stripe_event_id, :event_type, :livemode, :status, :error_reason])
    |> validate_required([:provider, :stripe_event_id, :event_type, :livemode, :status])
    |> validate_inclusion(:provider, ["stripe"])
    |> validate_inclusion(:status, ["received", "processed", "ignored", "failed"])
    |> unique_constraint([:provider, :stripe_event_id])
  end
end
```

- [ ] **Step 5: Add webhook recording and timestamp tolerance**

In `lib/sticker/payments.ex`, add alias:

```elixir
  alias Sticker.Payments.PaymentWebhookEvent
```

Add public function:

```elixir
  def record_webhook_event(%{"id" => event_id, "type" => event_type} = event) do
    %PaymentWebhookEvent{}
    |> PaymentWebhookEvent.changeset(%{
      provider: "stripe",
      stripe_event_id: event_id,
      event_type: event_type,
      livemode: Map.get(event, "livemode", false),
      status: "received"
    })
    |> Repo.insert()
    |> case do
      {:ok, webhook_event} -> {:ok, webhook_event}
      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :provider) or Keyword.has_key?(errors, :stripe_event_id) do
          {:error, :duplicate_event}
        else
          {:error, :invalid_event}
        end
    end
  end
```

Replace `verify_webhook/2` with timestamp tolerance:

```elixir
  def verify_webhook(payload, signature) when is_binary(signature) do
    with {:ok, secret} <- System.fetch_env("STRIPE_WEBHOOK_SECRET"),
         %{"t" => timestamp, "v1" => expected} <- parse_signature(signature),
         {timestamp, ""} <- Integer.parse(timestamp),
         true <- fresh_signature_timestamp?(timestamp),
         signed_payload = "#{timestamp}.#{payload}",
         digest <-
           :crypto.mac(:hmac, :sha256, secret, signed_payload) |> Base.encode16(case: :lower),
         true <- Plug.Crypto.secure_compare(digest, expected) do
      Jason.decode(payload)
    else
      _ -> {:error, :invalid_signature}
    end
  end
```

Add helper:

```elixir
  defp fresh_signature_timestamp?(timestamp) do
    abs(System.system_time(:second) - timestamp) <= 300
  end
```

Update existing signature tests to use `Integer.to_string(System.system_time(:second))` instead of fixed `"1710000000"` where the expected result should be success.

- [ ] **Step 6: Run tests**

Run:

```bash
mix ecto.migrate
mix test test/emoji/payments_test.exs
```

Expected: all domain tests pass.

- [ ] **Step 7: Commit Task 3**

Run:

```bash
git add priv/repo/migrations/20260613130500_create_payment_webhook_events.exs lib/sticker/payments/payment_webhook_event.ex lib/sticker/payments.ex test/emoji/payments_test.exs
git commit -m "Record Stripe webhook events safely"
```

---

### Task 4: Validate Stripe Checkout Before Crediting

**Files:**
- Modify: `lib/sticker/payments/payment_event.ex`
- Create: `priv/repo/migrations/20260613131000_harden_payment_events.exs`
- Modify: `lib/sticker/payments.ex`
- Test: `test/emoji/payments_test.exs`

- [ ] **Step 1: Write failing validation tests**

Add tests:

```elixir
  test "fulfill_checkout/2 rejects unpaid Stripe checkout sessions" do
    user = user_fixture()
    plan = Payments.get_plan("starter")
    {:ok, attempt} = Payments.create_payment_attempt(plan, user)
    {:ok, _attempt} = Payments.mark_payment_attempt_open(attempt, %{"id" => "cs_unpaid"})

    session = stripe_paid_session(%{
      "id" => "cs_unpaid",
      "payment_status" => "unpaid",
      "metadata" => %{
        "user_id" => Integer.to_string(user.id),
        "credits" => "50",
        "plan" => "starter",
        "payment_attempt_id" => Integer.to_string(attempt.id)
      }
    })

    assert {:error, :unpaid_checkout} = Payments.fulfill_checkout(session, "evt_unpaid")
    assert Accounts.get_user(user.id).credits == user.credits
  end

  test "fulfill_checkout/2 rejects sessions with mismatched price or amount" do
    user = user_fixture()
    plan = Payments.get_plan("starter")
    {:ok, attempt} = Payments.create_payment_attempt(plan, user)
    {:ok, _attempt} = Payments.mark_payment_attempt_open(attempt, %{"id" => "cs_bad_price"})

    session = stripe_paid_session(%{
      "id" => "cs_bad_price",
      "amount_total" => 399,
      "metadata" => %{
        "user_id" => Integer.to_string(user.id),
        "credits" => "50",
        "plan" => "starter",
        "payment_attempt_id" => Integer.to_string(attempt.id)
      }
    })

    assert {:error, :checkout_amount_mismatch} = Payments.fulfill_checkout(session, "evt_bad_price")
    assert Accounts.get_user(user.id).credits == user.credits
  end

  defp stripe_paid_session(overrides) do
    Map.merge(
      %{
        "id" => "cs_test_paid",
        "mode" => "payment",
        "payment_status" => "paid",
        "payment_intent" => "pi_test_paid",
        "amount_total" => 499,
        "currency" => "usd",
        "metadata" => %{
          "user_id" => "0",
          "credits" => "50",
          "plan" => "starter",
          "payment_attempt_id" => "0"
        }
      },
      overrides
    )
  end
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: tests fail because `fulfill_checkout/2` currently trusts metadata and does not check paid/amount.

- [ ] **Step 3: Add ledger fields migration**

Create `priv/repo/migrations/20260613131000_harden_payment_events.exs`:

```elixir
defmodule Sticker.Repo.Migrations.HardenPaymentEvents do
  use Ecto.Migration

  def change do
    alter table(:payment_events) do
      add :payment_attempt_id, references(:payment_attempts, on_delete: :nothing)
      add :amount, :integer
      add :currency, :string
      add :stripe_price_id, :string
    end

    create index(:payment_events, [:payment_attempt_id])
  end
end
```

- [ ] **Step 4: Update payment event schema**

In `lib/sticker/payments/payment_event.ex`, add fields:

```elixir
    field :payment_attempt_id, :integer
    field :amount, :integer
    field :currency, :string
    field :stripe_price_id, :string
```

Add them to `cast/3`:

```elixir
      :payment_attempt_id,
      :amount,
      :currency,
      :stripe_price_id,
```

Extend refund status inclusion:

```elixir
    |> validate_inclusion(:refund_status, ["none", "refunded", "review_required", "partial_refund_review"])
```

- [ ] **Step 5: Replace checkout fulfillment with validation**

In `lib/sticker/payments.ex`, replace `fulfill_checkout/2` with:

```elixir
  def fulfill_checkout(
        %{
          "id" => session_id,
          "metadata" => %{
            "user_id" => user_id,
            "credits" => credits,
            "plan" => plan_id,
            "payment_attempt_id" => attempt_id
          }
        } = session,
        stripe_event_id
      ) do
    with {attempt_id, ""} <- Integer.parse(attempt_id),
         {user_id, ""} <- Integer.parse(user_id),
         {credits, ""} <- Integer.parse(credits),
         %PaymentAttempt{} = attempt <- Repo.get(PaymentAttempt, attempt_id),
         :ok <- validate_checkout_session(session, attempt, user_id, credits, plan_id) do
      credit_validated_checkout(session, attempt, stripe_event_id)
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :payment_attempt_not_found}
      _error -> {:error, :invalid_checkout_metadata}
    end
  end
```

Add helpers:

```elixir
  defp validate_checkout_session(session, attempt, user_id, credits, plan_id) do
    cond do
      session["payment_status"] != "paid" ->
        {:error, :unpaid_checkout}

      session["mode"] != "payment" ->
        {:error, :invalid_checkout_mode}

      session["id"] != attempt.stripe_session_id ->
        {:error, :checkout_session_mismatch}

      user_id != attempt.user_id ->
        {:error, :checkout_user_mismatch}

      credits != attempt.credits ->
        {:error, :checkout_credits_mismatch}

      plan_id != attempt.plan ->
        {:error, :checkout_plan_mismatch}

      session["amount_total"] != attempt.amount ->
        {:error, :checkout_amount_mismatch}

      String.downcase(to_string(session["currency"])) != attempt.currency ->
        {:error, :checkout_currency_mismatch}

      true ->
        :ok
    end
  end

  defp credit_validated_checkout(session, attempt, stripe_event_id) do
    Multi.new()
    |> Multi.insert(
      :payment_event,
      PaymentEvent.changeset(%PaymentEvent{}, %{
        stripe_session_id: attempt.stripe_session_id,
        stripe_event_id: stripe_event_id,
        provider: "stripe",
        provider_order_id: session["payment_intent"] || attempt.provider_order_id,
        payment_attempt_id: attempt.id,
        user_id: attempt.user_id,
        credits: attempt.credits,
        plan: attempt.plan,
        amount: attempt.amount,
        currency: attempt.currency,
        stripe_price_id: attempt.stripe_price_id
      })
    )
    |> Multi.run(:credits, fn _repo, _changes ->
      Accounts.add_credits(attempt.user_id, attempt.credits)
    end)
    |> Multi.update(:attempt, fn _changes ->
      PaymentAttempt.changeset(attempt, %{status: "credited"})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, :payment_event, %Ecto.Changeset{}, _changes} -> :ok
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end
```

Update older tests that call `fulfill_checkout/2` to first create and open a payment attempt, then include `"payment_attempt_id"` plus `"payment_status"`, `"mode"`, `"amount_total"`, and `"currency"` in the session. Keep tests explicit; do not add shortcuts that hide the validation being tested.

- [ ] **Step 6: Run tests**

Run:

```bash
mix ecto.migrate
mix test test/emoji/payments_test.exs
```

Expected: all payment domain tests pass.

- [ ] **Step 7: Commit Task 4**

Run:

```bash
git add priv/repo/migrations/20260613131000_harden_payment_events.exs lib/sticker/payments/payment_event.ex lib/sticker/payments.ex test/emoji/payments_test.exs
git commit -m "Validate Stripe checkout before crediting"
```

---

### Task 5: Harden Stripe Webhook Controller Behavior

**Files:**
- Modify: `lib/sticker_web/controllers/stripe_webhook_controller.ex`
- Modify: `test/emoji_web/controllers/stripe_webhook_controller_test.exs`

- [ ] **Step 1: Write failing controller tests**

Add tests:

```elixir
  test "POST /webhooks/stripe ignores duplicate event ids without re-crediting", %{conn: conn} do
    user = user_fixture()
    plan = Payments.get_plan("starter")
    {:ok, attempt} = Payments.create_payment_attempt(plan, user)
    {:ok, _attempt} = Payments.mark_payment_attempt_open(attempt, %{"id" => "cs_duplicate_webhook"})

    payload =
      Jason.encode!(%{
        "id" => "evt_duplicate_webhook",
        "type" => "checkout.session.completed",
        "livemode" => false,
        "data" => %{
          "object" => %{
            "id" => "cs_duplicate_webhook",
            "mode" => "payment",
            "payment_status" => "paid",
            "payment_intent" => "pi_duplicate_webhook",
            "amount_total" => 499,
            "currency" => "usd",
            "metadata" => %{
              "user_id" => Integer.to_string(user.id),
              "credits" => "50",
              "plan" => "starter",
              "payment_attempt_id" => Integer.to_string(attempt.id)
            }
          }
        }
      })

    conn =
      conn
      |> put_req_header("stripe-signature", stripe_signature(payload))
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 200) == "ok"

    conn =
      build_conn()
      |> put_req_header("stripe-signature", stripe_signature(payload))
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 200) == "ok"
    assert Accounts.get_user(user.id).credits == user.credits + 50
  end

  test "POST /webhooks/stripe returns 200 for supported event with invalid business data after recording it", %{conn: conn} do
    payload =
      Jason.encode!(%{
        "id" => "evt_bad_business_data",
        "type" => "checkout.session.completed",
        "livemode" => false,
        "data" => %{"object" => %{"id" => "cs_missing_metadata"}}
      })

    conn =
      conn
      |> put_req_header("stripe-signature", stripe_signature(payload))
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 200) == "ok"
  end
```

Update `stripe_signature/1` to use the current timestamp:

```elixir
    timestamp = Integer.to_string(System.system_time(:second))
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
mix test test/emoji_web/controllers/stripe_webhook_controller_test.exs
```

Expected: duplicate webhook event handling fails until controller records webhook events.

- [ ] **Step 3: Record webhook events in the controller**

Replace `handle/2` with:

```elixir
  def handle(conn, _params) do
    with payload when is_binary(payload) <- conn.private[:raw_body],
         signature when is_binary(signature) <-
           get_req_header(conn, "stripe-signature") |> List.first(),
         {:ok, event} <- Payments.verify_webhook(payload, signature) do
      case Payments.record_webhook_event(event) do
        {:ok, _webhook_event} ->
          handle_event(event)

        {:error, :duplicate_event} ->
          :ok

        {:error, _reason} ->
          :ok
      end

      send_resp(conn, 200, "ok")
    else
      _error -> send_resp(conn, 400, "bad request")
    end
  end
```

Keep `handle_event/1` returning `:ok` or `{:error, reason}`; the controller deliberately returns 200 after signature verification so Stripe does not retry permanent business-rule failures forever. Admin review is handled by records.

- [ ] **Step 4: Run controller tests**

Run:

```bash
mix test test/emoji_web/controllers/stripe_webhook_controller_test.exs
```

Expected: all Stripe webhook controller tests pass.

- [ ] **Step 5: Commit Task 5**

Run:

```bash
git add lib/sticker_web/controllers/stripe_webhook_controller.ex test/emoji_web/controllers/stripe_webhook_controller_test.exs
git commit -m "Make Stripe webhook handling idempotent"
```

---

### Task 6: Classify Full, Partial, and Low-Balance Refunds

**Files:**
- Modify: `lib/sticker/payments.ex`
- Modify: `lib/sticker/payments/payment_event.ex`
- Test: `test/emoji/payments_test.exs`

- [ ] **Step 1: Write failing refund classification tests**

Add tests:

```elixir
  test "refund_stripe_checkout/2 marks partial refunds for manual review" do
    user = user_fixture()
    payment = paid_stripe_payment_for(user, "cs_partial_refund", "pi_partial_refund")

    refund_event = %{
      "id" => "evt_partial_refund",
      "type" => "charge.refunded",
      "data" => %{
        "object" => %{
          "id" => "ch_partial_refund",
          "payment_intent" => "pi_partial_refund",
          "amount" => payment.amount,
          "amount_refunded" => div(payment.amount, 2)
        }
      }
    }

    assert :ok = Payments.refund_stripe_checkout(refund_event, refund_event["id"])
    assert Accounts.get_user(user.id).credits == user.credits + payment.credits

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_partial_refund")
    assert payment.refund_status == "partial_refund_review"
    assert payment.refund_event_id == "evt_partial_refund"
  end

  defp paid_stripe_payment_for(user, session_id, payment_intent) do
    plan = Payments.get_plan("starter")
    {:ok, attempt} = Payments.create_payment_attempt(plan, user)
    {:ok, _attempt} = Payments.mark_payment_attempt_open(attempt, %{"id" => session_id, "payment_intent" => payment_intent})

    session =
      stripe_paid_session(%{
        "id" => session_id,
        "payment_intent" => payment_intent,
        "metadata" => %{
          "user_id" => Integer.to_string(user.id),
          "credits" => Integer.to_string(plan.credits),
          "plan" => plan.id,
          "payment_attempt_id" => Integer.to_string(attempt.id)
        }
      })

    assert :ok = Payments.fulfill_checkout(session, "evt_#{session_id}")
    Repo.get_by!(PaymentEvent, stripe_session_id: session_id)
  end
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: partial refund test fails because current refund code treats it like a full refund.

- [ ] **Step 3: Update refund status schema**

In `lib/sticker/payments/payment_event.ex`, ensure this line includes `partial_refund_review`:

```elixir
    |> validate_inclusion(:refund_status, ["none", "refunded", "review_required", "partial_refund_review"])
```

- [ ] **Step 4: Classify partial Stripe refunds**

Replace `refund_stripe_checkout/2` with:

```elixir
  def refund_stripe_checkout(event, refund_event_id) do
    charge = get_in(event, ["data", "object"]) || Map.get(event, "object", event)
    payment_intent = charge["payment_intent"]
    charge_id = charge["id"]

    cond do
      partial_stripe_refund?(charge) ->
        mark_refund_review("stripe", payment_intent, charge_id, refund_event_id, "partial_refund_review")

      true ->
        refund_provider_checkout("stripe", payment_intent, charge_id, refund_event_id)
    end
  end
```

Add helpers:

```elixir
  defp partial_stripe_refund?(%{"amount" => amount, "amount_refunded" => refunded})
       when is_integer(amount) and is_integer(refunded) do
    refunded > 0 and refunded < amount
  end

  defp partial_stripe_refund?(_charge), do: false

  defp mark_refund_review(provider, order_id, checkout_id, refund_event_id, status) do
    import Ecto.Query

    query =
      from e in PaymentEvent,
        where: e.provider == ^provider,
        where: e.refund_status == "none",
        limit: 1

    query =
      cond do
        is_binary(order_id) and order_id != "" ->
          from e in query, where: e.provider_order_id == ^order_id

        is_binary(checkout_id) and checkout_id != "" ->
          from e in query, where: e.stripe_session_id == ^checkout_id

        true ->
          query
      end

    case Repo.one(query) do
      %PaymentEvent{} = payment ->
        payment
        |> PaymentEvent.changeset(%{
          refunded_at: DateTime.utc_now() |> DateTime.truncate(:second),
          refund_event_id: refund_event_id,
          refund_status: status
        })
        |> Repo.update()
        |> case do
          {:ok, _payment} -> :ok
          {:error, %Ecto.Changeset{}} -> :ok
        end

      nil ->
        :ok
    end
  end
```

- [ ] **Step 5: Run tests**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: refund tests pass, including full refund, low-balance review, and partial refund review.

- [ ] **Step 6: Commit Task 6**

Run:

```bash
git add lib/sticker/payments.ex lib/sticker/payments/payment_event.ex test/emoji/payments_test.exs
git commit -m "Classify Stripe refund outcomes"
```

---

### Task 7: Show Checkout and Refund States to Users

**Files:**
- Modify: `lib/sticker/payments.ex`
- Modify: `lib/sticker_web/controllers/page_controller.ex`
- Modify: `lib/sticker_web/controllers/page_html/pricing.html.heex`
- Modify: `lib/sticker_web/live/account_live.ex`
- Modify: `lib/sticker_web/live/account_live.html.heex`
- Modify: `test/emoji_web/controllers/page_controller_test.exs`

- [ ] **Step 1: Add payment attempt query functions**

In `lib/sticker/payments.ex`, add:

```elixir
  def list_user_payment_attempts(user_id) do
    import Ecto.Query

    Repo.all(
      from a in PaymentAttempt,
        where: a.user_id == ^user_id,
        order_by: [desc: a.inserted_at],
        limit: 20
    )
  end
```

- [ ] **Step 2: Add pricing feedback tests**

In `test/emoji_web/controllers/page_controller_test.exs`, add:

```elixir
  test "GET /pricing shows canceled checkout feedback", %{conn: conn} do
    conn = get(conn, ~p"/pricing?checkout=canceled")

    assert html_response(conn, 200) =~ "Checkout canceled"
    assert html_response(conn, 200) =~ "You were not charged"
  end
```

- [ ] **Step 3: Run page test to verify RED**

Run:

```bash
mix test test/emoji_web/controllers/page_controller_test.exs
```

Expected: test fails because pricing page does not render checkout feedback.

- [ ] **Step 4: Assign checkout status on pricing page**

In `lib/sticker_web/controllers/page_controller.ex`, replace the existing `pricing/2` function:

```elixir
  def pricing(conn, params) do
    conn
    |> SEO.assign(
      PageSEO.page("/pricing",
        title: "AI Sticker Maker Pricing - Buy Sticker Credits",
        description:
          "View AI Sticker Maker pricing, free starter credits, and paid credit packs for text-to-sticker and face-to-sticker generation."
      )
    )
    |> render(:pricing, checkout: Map.get(params, "checkout"))
  end
```

- [ ] **Step 5: Render pricing feedback**

In `lib/sticker_web/controllers/page_html/pricing.html.heex`, below the pricing hero and before `.saas-buy-grid`, add:

```heex
    <div :if={@checkout == "canceled"} class="saas-buy-note">
      <strong>Checkout canceled:</strong>
      You were not charged. You can choose a plan whenever you are ready.
    </div>
```

- [ ] **Step 6: Show attempts and statuses on account page**

In `lib/sticker_web/live/account_live.ex`, assign attempts in `mount/3` and `refresh_account_data/2`:

```elixir
     |> assign(:payment_attempts, Payments.list_user_payment_attempts(user.id))
```

Add status helper:

```elixir
  defp attempt_status(%{status: "created"}), do: "Checkout started"
  defp attempt_status(%{status: "open"}), do: "Checkout open"
  defp attempt_status(%{status: "completed"}), do: "Payment received"
  defp attempt_status(%{status: "credited"}), do: "Credits added"
  defp attempt_status(%{status: "canceled"}), do: "Canceled"
  defp attempt_status(%{status: "expired"}), do: "Expired"
  defp attempt_status(%{status: "failed"}), do: "Failed"
```

Update payment status helper:

```elixir
  defp payment_status(%{refund_status: "refunded"}), do: "Refunded"
  defp payment_status(%{refund_status: "review_required"}), do: "Review required"
  defp payment_status(%{refund_status: "partial_refund_review"}), do: "Partial refund review"
  defp payment_status(_payment), do: "Paid"
```

In `lib/sticker_web/live/account_live.html.heex`, update the payment copy:

```heex
      <p class="saas-section-copy">Checkout attempts, completed payments, and refund status for this account.</p>
```

Add an attempts table before the completed payment table:

```heex
    <div class="admin-table-wrap">
      <table class="admin-table">
        <thead>
          <tr>
            <th>Plan</th>
            <th>Credits</th>
            <th>Status</th>
            <th>Checkout ID</th>
            <th>Date</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={attempt <- @payment_attempts}>
            <td><%= attempt.plan %></td>
            <td><%= attempt.credits %></td>
            <td><%= attempt_status(attempt) %></td>
            <td><code><%= attempt.stripe_session_id || "-" %></code></td>
            <td><%= Calendar.strftime(attempt.inserted_at, "%Y-%m-%d") %></td>
          </tr>
          <tr :if={@payment_attempts == []}>
            <td colspan="5">No checkout attempts yet.</td>
          </tr>
        </tbody>
      </table>
    </div>
```

- [ ] **Step 7: Run page and LiveView-related tests**

Run:

```bash
mix test test/emoji_web/controllers/page_controller_test.exs
```

Expected: page controller tests pass. If LiveView tests exist for account, run them too.

- [ ] **Step 8: Commit Task 7**

Run:

```bash
git add lib/sticker/payments.ex lib/sticker_web/controllers/page_controller.ex lib/sticker_web/controllers/page_html/pricing.html.heex lib/sticker_web/live/account_live.ex lib/sticker_web/live/account_live.html.heex test/emoji_web/controllers/page_controller_test.exs
git commit -m "Show payment lifecycle states to users"
```

---

### Task 8: Show Review States in Admin

**Files:**
- Modify: `lib/sticker/payments.ex`
- Modify: `lib/sticker_web/live/admin_payments_live.ex`
- Modify: `lib/sticker_web/live/admin_payments_live.html.heex`

- [ ] **Step 1: Add admin attempt query**

In `lib/sticker/payments.ex`, add:

```elixir
  def list_payment_attempts(limit \\ 200) do
    import Ecto.Query

    Repo.all(
      from a in PaymentAttempt,
        order_by: [desc: a.inserted_at],
        limit: ^limit
    )
  end
```

- [ ] **Step 2: Assign attempts to admin page**

In `lib/sticker_web/live/admin_payments_live.ex`, update mount:

```elixir
     |> assign(:payments, Payments.list_payment_events(200))
     |> assign(:attempts, Payments.list_payment_attempts(200))
     |> assign(:users, users)}
```

Add status helper:

```elixir
  defp payment_status(%{refund_status: "partial_refund_review"}), do: "Partial refund review"
```

- [ ] **Step 3: Render attempts and review statuses**

In `lib/sticker_web/live/admin_payments_live.html.heex`, update description:

```heex
      <p>Review checkout attempts, paid credit events, and refund cases that need attention.</p>
```

Add a checkout attempts table above the payment records table with columns:

```heex
<h2>Checkout Attempts</h2>
<div class="admin-table-wrap">
  <table class="admin-table">
    <thead>
      <tr>
        <th>User</th>
        <th>Plan</th>
        <th>Credits</th>
        <th>Status</th>
        <th>Checkout ID</th>
        <th>Failure</th>
        <th>Date</th>
      </tr>
    </thead>
    <tbody>
      <tr :for={attempt <- @attempts}>
        <td><%= if user = @users[attempt.user_id], do: user.email, else: "Unknown user" %></td>
        <td><%= attempt.plan %></td>
        <td><span class="saas-credit-pill"><%= attempt.credits %></span></td>
        <td><%= attempt.status %></td>
        <td><code><%= attempt.stripe_session_id || "-" %></code></td>
        <td><%= attempt.failure_reason || "-" %></td>
        <td><%= Calendar.strftime(attempt.inserted_at, "%Y-%m-%d %H:%M") %></td>
      </tr>
      <tr :if={@attempts == []}>
        <td colspan="7">No checkout attempts yet.</td>
      </tr>
    </tbody>
  </table>
</div>
```

- [ ] **Step 4: Run compile**

Run:

```bash
mix compile --warnings-as-errors
```

Expected: compile succeeds.

- [ ] **Step 5: Commit Task 8**

Run:

```bash
git add lib/sticker/payments.ex lib/sticker_web/live/admin_payments_live.ex lib/sticker_web/live/admin_payments_live.html.heex
git commit -m "Expose payment review states in admin"
```

---

### Task 9: Documentation and Operational Checklist

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README with production payment checklist**

Add this section under Stripe payment setup:

```markdown
### Production payment checklist

Before enabling public paid traffic:

1. Confirm Stripe live mode has these webhook events enabled:
   - `checkout.session.completed`
   - `charge.refunded`
2. Run a live minimum-value purchase from the deployed domain.
3. Confirm `/account` shows the checkout attempt and the credited payment.
4. Refund that live payment from Stripe Dashboard.
5. Confirm `/account` and `/admin/payments` show the refund state.
6. Rotate any live Stripe secret key that was copied into chat, tickets, logs, or screenshots.
7. Update the deployed `STRIPE_SECRET_KEY` after rotation and restart the app.

Refund policy in code:

- Full refunds automatically remove the original purchased credits if the account balance can cover them.
- Low-balance refunds are marked `review_required`.
- Partial refunds are marked `partial_refund_review`; credits are not automatically changed.
```

- [ ] **Step 2: Review README diff**

Run:

```bash
git diff -- README.md
```

Expected: only payment documentation changed.

- [ ] **Step 3: Commit Task 9**

Run:

```bash
git add README.md
git commit -m "Document hardened payment operations"
```

---

### Task 10: Final Verification

**Files:**
- Verify all touched files.

- [ ] **Step 1: Run migrations in test database**

Run:

```bash
MIX_ENV=test mix ecto.reset
```

Expected: test database resets and all migrations run successfully.

- [ ] **Step 2: Run focused tests**

Run:

```bash
mix test test/emoji/payments_test.exs test/emoji_web/controllers/stripe_webhook_controller_test.exs test/emoji_web/controllers/page_controller_test.exs
```

Expected: all focused tests pass.

- [ ] **Step 3: Run full test suite**

Run:

```bash
$env:BUCKET_NAME="test-bucket"; mix test
```

Expected: full test suite passes.

- [ ] **Step 4: Check formatting for touched files**

Run:

```bash
mix format lib/sticker/payments.ex lib/sticker/payments/payment_attempt.ex lib/sticker/payments/payment_event.ex lib/sticker/payments/payment_webhook_event.ex lib/sticker_web/controllers/checkout_controller.ex lib/sticker_web/controllers/stripe_webhook_controller.ex lib/sticker_web/controllers/page_controller.ex lib/sticker_web/live/account_live.ex lib/sticker_web/live/admin_payments_live.ex test/emoji/payments_test.exs test/emoji_web/controllers/stripe_webhook_controller_test.exs test/emoji_web/controllers/page_controller_test.exs
```

Expected: command completes. Do not run repo-wide formatting unless the repo is already fully formatted.

- [ ] **Step 5: Inspect git status**

Run:

```bash
git status --short
```

Expected: only intentional files are modified or newly added.

---

## Self-Review

- Spec coverage: The plan covers user-visible states, strict webhook validation, idempotency, full refund automation, partial refund review, low-balance review, admin visibility, tests, and production operations.
- Placeholder scan: No task says TBD/TODO or asks for vague "appropriate" handling without concrete code or expected behavior.
- Type consistency: New schemas are `PaymentAttempt` and `PaymentWebhookEvent`; payment statuses and refund statuses are repeated consistently across schema, domain code, and UI helpers.
- Simplicity check: This plan adds two focused tables instead of a generic payment framework. It keeps existing `PaymentEvent` rather than replacing it, and it defers partial-refund credit math to manual review.
