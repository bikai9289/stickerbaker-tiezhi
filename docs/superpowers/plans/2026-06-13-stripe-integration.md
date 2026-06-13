# Stripe Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Stripe the production-ready checkout provider for credit purchases, including payment fulfillment, refund bookkeeping, tests, and deployment documentation.

**Architecture:** Keep the existing `Sticker.Payments` context as the payment boundary. Stripe Checkout creation and webhook verification already live there; this plan extends fulfillment to store a Stripe refund lookup ID and adds Stripe refund processing that reuses the current provider refund bookkeeping. The Stripe webhook controller remains a thin event dispatcher.

**Tech Stack:** Elixir, Phoenix 1.7, Ecto, ExUnit, Req for Stripe API calls, Plug/Phoenix controller tests.

---

## File Structure

- Modify `test/emoji/payments_test.exs`: add Stripe fulfillment, signature, and refund behavior tests.
- Modify `lib/sticker/payments.ex`: store Stripe `payment_intent` on fulfillment, add `refund_stripe_checkout/2`, and let refund lookup use `provider_order_id` or session ID.
- Modify `lib/sticker_web/controllers/stripe_webhook_controller.ex`: dispatch `charge.refunded` events to `Payments.refund_stripe_checkout/2`.
- Modify `README.md`: document Stripe Dashboard setup and required production environment variables.

No schema migration is planned. `payment_events.provider_order_id` already exists and will store the Stripe payment intent ID for refund lookup.

---

### Task 1: Add Stripe Fulfillment Tests

**Files:**
- Modify: `test/emoji/payments_test.exs`

- [ ] **Step 1: Write failing tests for Stripe fulfillment and idempotency**

Add these tests after the aliases/imports and before the existing Creem tests:

```elixir
  test "fulfill_checkout/2 adds credits and records Stripe provider details" do
    user = user_fixture()

    session = %{
      "id" => "cs_test_123",
      "payment_intent" => "pi_test_123",
      "metadata" => %{
        "user_id" => Integer.to_string(user.id),
        "credits" => "50",
        "plan" => "starter"
      }
    }

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_checkout")
    assert Accounts.get_user(user.id).credits == user.credits + 50

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_123")
    assert payment.provider == "stripe"
    assert payment.provider_order_id == "pi_test_123"
    assert payment.stripe_event_id == "evt_stripe_checkout"
    assert payment.credits == 50
    assert payment.plan == "starter"
  end

  test "fulfill_checkout/2 is idempotent for duplicate Stripe checkout webhooks" do
    user = user_fixture()

    session = %{
      "id" => "cs_test_duplicate",
      "payment_intent" => "pi_test_duplicate",
      "metadata" => %{
        "user_id" => Integer.to_string(user.id),
        "credits" => "50",
        "plan" => "starter"
      }
    }

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_checkout_duplicate_1")
    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_checkout_duplicate_2")
    assert Accounts.get_user(user.id).credits == user.credits + 50
  end
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: the first new test fails because `payment.provider_order_id` is `nil`; the duplicate test may already pass.

- [ ] **Step 3: Implement minimal Stripe fulfillment storage**

In `lib/sticker/payments.ex`, update `fulfill_checkout/2` so the inserted `PaymentEvent` includes `provider_order_id`:

```elixir
          provider: "stripe",
          provider_order_id: session["payment_intent"],
          user_id: user_id,
```

The full function head should keep the `session` binding available:

```elixir
  def fulfill_checkout(
        %{
          "id" => session_id,
          "metadata" => %{"user_id" => user_id, "credits" => credits} = metadata
        } = session,
        stripe_event_id
      ) do
```

- [ ] **Step 4: Run tests to verify GREEN**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: all tests in `test/emoji/payments_test.exs` pass.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add test/emoji/payments_test.exs lib/sticker/payments.ex
git commit -m "Store Stripe payment intent on fulfillment"
```

---

### Task 2: Add Stripe Webhook Signature Test

**Files:**
- Modify: `test/emoji/payments_test.exs`

- [ ] **Step 1: Write failing test for Stripe signature verification**

Add this test near the existing `verify_creem_webhook/2` test:

```elixir
  test "verify_webhook/2 validates Stripe signed payloads" do
    secret = System.get_env("STRIPE_WEBHOOK_SECRET")

    on_exit(fn ->
      restore_env("STRIPE_WEBHOOK_SECRET", secret)
    end)

    System.put_env("STRIPE_WEBHOOK_SECRET", "whsec_stripe_test")
    payload = ~s({"type":"checkout.session.completed"})
    timestamp = "1710000000"

    digest =
      :crypto.mac(:hmac, :sha256, "whsec_stripe_test", "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    signature = "t=#{timestamp},v1=#{digest}"

    assert {:ok, %{"type" => "checkout.session.completed"}} =
             Payments.verify_webhook(payload, signature)

    assert {:error, :invalid_signature} = Payments.verify_webhook(payload, "t=#{timestamp},v1=bad")
  end
```

- [ ] **Step 2: Run test to verify behavior**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: this test should pass with the existing implementation. If it fails, fix only `Payments.verify_webhook/2` so it accepts the valid signature and rejects the invalid one.

- [ ] **Step 3: Commit Task 2**

Run:

```bash
git add test/emoji/payments_test.exs lib/sticker/payments.ex
git commit -m "Test Stripe webhook signature verification"
```

---

### Task 3: Add Stripe Refund Domain Tests

**Files:**
- Modify: `test/emoji/payments_test.exs`
- Modify: `lib/sticker/payments.ex`

- [ ] **Step 1: Write failing tests for Stripe refund bookkeeping**

Add these tests after the Stripe fulfillment tests:

```elixir
  test "refund_stripe_checkout/2 deducts original credits when balance can cover refund" do
    user = user_fixture()

    session = %{
      "id" => "cs_test_refund",
      "payment_intent" => "pi_test_refund",
      "metadata" => %{
        "user_id" => Integer.to_string(user.id),
        "credits" => "50",
        "plan" => "starter"
      }
    }

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_checkout_refund")
    assert Accounts.get_user(user.id).credits == user.credits + 50

    refund_event = %{
      "id" => "evt_stripe_refund",
      "type" => "charge.refunded",
      "data" => %{
        "object" => %{
          "id" => "ch_test_refund",
          "payment_intent" => "pi_test_refund"
        }
      }
    }

    assert :ok = Payments.refund_stripe_checkout(refund_event, refund_event["id"])
    assert Accounts.get_user(user.id).credits == user.credits

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_refund")
    assert payment.refund_event_id == "evt_stripe_refund"
    assert payment.refunded_at
    assert payment.refund_status == "refunded"

    assert :ok = Payments.refund_stripe_checkout(refund_event, refund_event["id"])
    assert Accounts.get_user(user.id).credits == user.credits
  end

  test "refund_stripe_checkout/2 marks review required when balance is too low" do
    user = user_fixture()

    session = %{
      "id" => "cs_test_low_balance_refund",
      "payment_intent" => "pi_test_low_balance_refund",
      "metadata" => %{
        "user_id" => Integer.to_string(user.id),
        "credits" => "50",
        "plan" => "starter"
      }
    }

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_low_balance_checkout")

    {:ok, user_after_spend} = Accounts.deduct_credits(user.id, user.credits + 30)
    assert user_after_spend.credits == 20

    refund_event = %{
      "id" => "evt_stripe_low_balance_refund",
      "type" => "charge.refunded",
      "data" => %{
        "object" => %{
          "id" => "ch_test_low_balance_refund",
          "payment_intent" => "pi_test_low_balance_refund"
        }
      }
    }

    assert :ok = Payments.refund_stripe_checkout(refund_event, refund_event["id"])
    assert Accounts.get_user(user.id).credits == 20

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_low_balance_refund")
    assert payment.refund_event_id == "evt_stripe_low_balance_refund"
    assert payment.refunded_at
    assert payment.refund_status == "review_required"
  end
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: compilation fails because `Payments.refund_stripe_checkout/2` is undefined.

- [ ] **Step 3: Implement minimal Stripe refund extraction**

In `lib/sticker/payments.ex`, add this public function near `refund_creem_checkout/2`:

```elixir
  def refund_stripe_checkout(event, refund_event_id) do
    charge = get_in(event, ["data", "object"]) || Map.get(event, "object", event)
    payment_intent = charge["payment_intent"]
    charge_id = charge["id"]

    refund_provider_checkout("stripe", payment_intent, charge_id, refund_event_id)
  end
```

- [ ] **Step 4: Update refund lookup to support Stripe payment intents**

In `do_refund_provider_checkout/4`, rename the first argument from `order_id` to `provider_order_id` and keep `checkout_id` as the fallback. Update the lookup condition so it queries `provider_order_id` first, then `stripe_session_id`:

```elixir
  defp do_refund_provider_checkout(provider, provider_order_id, checkout_id, refund_event_id) do
    Multi.new()
    |> Multi.run(:payment_event, fn repo, _changes ->
      import Ecto.Query

      query =
        from e in PaymentEvent,
          where: e.provider == ^provider,
          where: e.refund_status == "none",
          limit: 1

      query =
        cond do
          is_binary(provider_order_id) and provider_order_id != "" ->
            from e in query, where: e.provider_order_id == ^provider_order_id

          is_binary(checkout_id) and checkout_id != "" ->
            from e in query, where: e.stripe_session_id == ^checkout_id

          true ->
            query
        end
```

Keep the rest of the function body unchanged.

- [ ] **Step 5: Run tests to verify GREEN**

Run:

```bash
mix test test/emoji/payments_test.exs
```

Expected: all tests in `test/emoji/payments_test.exs` pass.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add test/emoji/payments_test.exs lib/sticker/payments.ex
git commit -m "Handle Stripe refund bookkeeping"
```

---

### Task 4: Wire Stripe Refund Webhook Controller

**Files:**
- Modify: `lib/sticker_web/controllers/stripe_webhook_controller.ex`
- Create: `test/emoji_web/controllers/stripe_webhook_controller_test.exs`

- [ ] **Step 1: Write failing controller tests**

Create `test/emoji_web/controllers/stripe_webhook_controller_test.exs`:

```elixir
defmodule StickerWeb.StripeWebhookControllerTest do
  use StickerWeb.ConnCase

  alias Sticker.Accounts
  alias Sticker.Payments
  alias Sticker.Payments.PaymentEvent
  alias Sticker.Repo

  import Sticker.AccountsFixtures

  test "POST /webhooks/stripe handles charge.refunded events", %{conn: conn} do
    user = user_fixture()

    session = %{
      "id" => "cs_controller_refund",
      "payment_intent" => "pi_controller_refund",
      "metadata" => %{
        "user_id" => Integer.to_string(user.id),
        "credits" => "50",
        "plan" => "starter"
      }
    }

    assert :ok = Payments.fulfill_checkout(session, "evt_controller_checkout")

    payload =
      Jason.encode!(%{
        "id" => "evt_controller_refund",
        "type" => "charge.refunded",
        "data" => %{
          "object" => %{
            "id" => "ch_controller_refund",
            "payment_intent" => "pi_controller_refund"
          }
        }
      })

    conn =
      conn
      |> put_req_header("stripe-signature", stripe_signature(payload))
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 200) == "ok"
    assert Accounts.get_user(user.id).credits == user.credits

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_controller_refund")
    assert payment.refund_status == "refunded"
    assert payment.refund_event_id == "evt_controller_refund"
  end

  test "POST /webhooks/stripe rejects invalid signatures", %{conn: conn} do
    payload = Jason.encode!(%{"id" => "evt_bad", "type" => "charge.refunded"})

    conn =
      conn
      |> put_req_header("stripe-signature", "t=1710000000,v1=bad")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 400) == "bad request"
  end

  defp stripe_signature(payload) do
    secret = System.get_env("STRIPE_WEBHOOK_SECRET")

    on_exit(fn ->
      restore_env("STRIPE_WEBHOOK_SECRET", secret)
    end)

    System.put_env("STRIPE_WEBHOOK_SECRET", "whsec_controller_test")
    timestamp = "1710000000"

    digest =
      :crypto.mac(:hmac, :sha256, "whsec_controller_test", "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{digest}"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
```

- [ ] **Step 2: Run controller test to verify RED**

Run:

```bash
mix test test/emoji_web/controllers/stripe_webhook_controller_test.exs
```

Expected: refund controller test fails because `charge.refunded` is ignored and the payment remains `refund_status == "none"`.

- [ ] **Step 3: Implement controller dispatch**

In `lib/sticker_web/controllers/stripe_webhook_controller.ex`, add this event handler below the checkout handler:

```elixir
  defp handle_event(%{"id" => event_id, "type" => "charge.refunded"} = event) do
    Payments.refund_stripe_checkout(event, event_id)
  end
```

- [ ] **Step 4: Run controller test to verify GREEN**

Run:

```bash
mix test test/emoji_web/controllers/stripe_webhook_controller_test.exs
```

Expected: both controller tests pass.

- [ ] **Step 5: Commit Task 4**

Run:

```bash
git add lib/sticker_web/controllers/stripe_webhook_controller.ex test/emoji_web/controllers/stripe_webhook_controller_test.exs
git commit -m "Dispatch Stripe refund webhooks"
```

---

### Task 5: Document Stripe Production Setup

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README payment setup**

Add this section after the existing Dev environment bullet list and before `## Prod`:

```markdown
## Stripe payments

Credit purchases use Stripe Checkout by default. Create two one-time Stripe prices in the Stripe Dashboard and configure these environment variables:

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_STARTER_PRICE_ID` for the Starter plan: 50 credits, USD 4.99
- `STRIPE_CREATOR_PRICE_ID` for the Creator plan: 150 credits, USD 9.99
- `PAYMENT_PROVIDER=stripe` is optional because Stripe is the default provider.

Add a Stripe webhook endpoint:

- URL: `https://<your-host>/webhooks/stripe`
- Events: `checkout.session.completed`, `charge.refunded`

For local webhook testing, run the Stripe CLI and forward events to the Phoenix server:

```bash
stripe listen --forward-to localhost:4000/webhooks/stripe
```

Use the signing secret printed by the Stripe CLI as `STRIPE_WEBHOOK_SECRET`.
```

- [ ] **Step 2: Review markdown formatting**

Run:

```bash
git diff -- README.md
```

Expected: README has one new Stripe payments section, with no unrelated changes.

- [ ] **Step 3: Commit Task 5**

Run:

```bash
git add README.md
git commit -m "Document Stripe payment setup"
```

---

### Task 6: Final Verification

**Files:**
- Verify all touched files.

- [ ] **Step 1: Run focused payment tests**

Run:

```bash
mix test test/emoji/payments_test.exs test/emoji_web/controllers/stripe_webhook_controller_test.exs test/emoji_web/controllers/page_controller_test.exs
```

Expected: all focused tests pass with no failures.

- [ ] **Step 2: Run full test suite**

Run:

```bash
mix test
```

Expected: full test suite passes.

- [ ] **Step 3: Check formatting**

Run:

```bash
mix format --check-formatted
```

Expected: command exits successfully. If it fails, run `mix format`, then repeat focused tests.

- [ ] **Step 4: Inspect git status**

Run:

```bash
git status --short
```

Expected: only intentional files are cleanly committed, except pre-existing untracked `img/` if it is still present.

---

## Self-Review

- Spec coverage: Checkout fulfillment, Stripe refunds, idempotency, webhook signature verification, controller dispatch, and README deployment documentation are covered.
- Placeholder scan: The plan avoids TBD/TODO placeholders and includes concrete test code and commands.
- Type consistency: Public functions are `Payments.fulfill_checkout/2`, `Payments.verify_webhook/2`, and `Payments.refund_stripe_checkout/2`; event fields match existing map-based code.
