defmodule Sticker.PaymentsTest do
  use Sticker.DataCase

  import Ecto.Query
  alias Sticker.Accounts
  alias Sticker.Payments
  alias Sticker.Payments.PaymentAttempt
  alias Sticker.Payments.PaymentEvent
  alias Sticker.Payments.PaymentWebhookEvent
  alias Sticker.Repo

  import Sticker.AccountsFixtures

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

  test "create_payment_attempt/2 records pending Stripe checkout details" do
    user = user_fixture()
    plan = Payments.get_plan("starter")

    assert {:ok, %PaymentAttempt{} = attempt} = Payments.create_payment_attempt(plan, user)

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
    {:ok, %PaymentAttempt{} = attempt} = Payments.create_payment_attempt(plan, user)

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

  test "list_user_payment_events/2 is newest-first and bounded" do
    user = user_fixture()
    other_user = user_fixture()
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    events =
      for {suffix, seconds_ago} <- [{"oldest", 120}, {"second", 60}, {"newest", 0}] do
        Repo.insert!(%PaymentEvent{
          stripe_session_id: "cs_test_list_#{suffix}",
          user_id: user.id,
          credits: 50,
          inserted_at: NaiveDateTime.add(now, -seconds_ago),
          updated_at: NaiveDateTime.add(now, -seconds_ago)
        })
      end

    Repo.insert!(%PaymentEvent{
      stripe_session_id: "cs_test_list_other_user",
      user_id: other_user.id,
      credits: 50,
      inserted_at: NaiveDateTime.add(now, 60),
      updated_at: NaiveDateTime.add(now, 60)
    })

    [oldest, second, newest] = events

    assert [first, next] = Payments.list_user_payment_events(user.id, 2)
    assert first.id == newest.id
    assert next.id == second.id
    refute oldest.id in [first.id, next.id]
  end

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
    assert request =~ "line_items%5B0%5D%5Bprice%5D=price_starter_test"

    attempt = Repo.get_by!(PaymentAttempt, stripe_session_id: "cs_test_create")
    assert attempt.status == "open"
    assert attempt.provider_order_id == "pi_test_create"
    assert request =~ "metadata%5Bpayment_attempt_id%5D=#{attempt.id}"
  end

  test "create_stripe_checkout_session/4 marks attempt failed when Stripe secret is missing" do
    user = user_fixture()
    plan = Payments.get_plan("starter")

    old_key = System.get_env("STRIPE_SECRET_KEY")
    System.delete_env("STRIPE_SECRET_KEY")
    on_exit(fn -> restore_env("STRIPE_SECRET_KEY", old_key) end)

    assert {:error, :checkout_not_configured} =
             Payments.create_stripe_checkout_session(
               plan,
               user,
               "https://example.com/account?checkout=success",
               "https://example.com/pricing?checkout=canceled"
             )

    attempt = Repo.get_by!(PaymentAttempt, user_id: user.id, plan: "starter")
    assert attempt.status == "failed"
    assert attempt.failure_reason == "checkout_not_configured"
  end

  test "fulfill_checkout/2 adds credits and records Stripe provider details" do
    user = user_fixture()

    {session, attempt} = stripe_paid_session_for(user, "cs_test_123", "pi_test_123")

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_checkout")
    assert Accounts.get_user(user.id).credits == user.credits + 50

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_123")
    assert payment.provider == "stripe"
    assert payment.provider_order_id == "pi_test_123"
    assert payment.stripe_event_id == "evt_stripe_checkout"
    assert payment.credits == 50
    assert payment.plan == "starter"
    assert payment.payment_attempt_id == attempt.id
    assert payment.amount == 499
    assert payment.currency == "usd"
    assert payment.stripe_price_id == "price_starter_test"

    attempt = Repo.get!(PaymentAttempt, attempt.id)
    assert attempt.status == "credited"
  end

  test "fulfill_checkout/2 is idempotent for duplicate Stripe checkout webhooks" do
    user = user_fixture()

    {session, attempt} = stripe_paid_session_for(user, "cs_test_duplicate", "pi_test_duplicate")

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_checkout_duplicate_1")
    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_checkout_duplicate_2")
    assert Accounts.get_user(user.id).credits == user.credits + 50

    assert [_payment] =
             Repo.all(
               from e in PaymentEvent,
                 where: e.stripe_session_id == "cs_test_duplicate"
             )

    attempt = Repo.get!(PaymentAttempt, attempt.id)
    assert attempt.status == "credited"
  end

  test "fulfill_checkout/2 rejects duplicate Stripe checkout with mismatched ledger fields" do
    user = user_fixture()

    {session, _attempt} =
      stripe_paid_session_for(user, "cs_test_duplicate_mismatch", "pi_test_duplicate_mismatch")

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_checkout_mismatch_1")

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_duplicate_mismatch")

    payment
    |> PaymentEvent.changeset(%{provider_order_id: "pi_test_tampered"})
    |> Repo.update!()

    assert {:error, :duplicate_checkout_mismatch} =
             Payments.fulfill_checkout(session, "evt_stripe_checkout_mismatch_2")

    assert Accounts.get_user(user.id).credits == user.credits + 50
  end

  test "fulfill_checkout/2 accepts expanded Stripe payment_intent objects" do
    user = user_fixture()

    {session, _attempt} = stripe_paid_session_for(user, "cs_test_expanded_pi", "pi_test_expanded")
    session = Map.put(session, "payment_intent", %{"id" => "pi_test_expanded"})

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_checkout_expanded_pi")

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_expanded_pi")
    assert payment.provider_order_id == "pi_test_expanded"
    assert Accounts.get_user(user.id).credits == user.credits + 50
  end

  test "fulfill_checkout/2 rejects mismatched Stripe payment intents" do
    user = user_fixture()

    {session, _attempt} = stripe_paid_session_for(user, "cs_test_pi_mismatch", "pi_test_original")
    session = Map.put(session, "payment_intent", "pi_test_mismatch")

    assert {:error, :checkout_payment_intent_mismatch} =
             Payments.fulfill_checkout(session, "evt_stripe_checkout_pi_mismatch")

    assert Accounts.get_user(user.id).credits == user.credits
  end

  test "fulfill_checkout/2 rejects unpaid Stripe checkout sessions" do
    user = user_fixture()
    {session, _attempt} = stripe_paid_session_for(user, "cs_unpaid", "pi_unpaid")
    session = Map.put(session, "payment_status", "unpaid")

    assert {:error, :unpaid_checkout} = Payments.fulfill_checkout(session, "evt_unpaid")
    assert Accounts.get_user(user.id).credits == user.credits
  end

  test "fulfill_checkout/2 rejects sessions with mismatched price or amount" do
    user = user_fixture()
    {session, _attempt} = stripe_paid_session_for(user, "cs_bad_price", "pi_bad_price")
    session = Map.put(session, "amount_total", 399)

    assert {:error, :checkout_amount_mismatch} = Payments.fulfill_checkout(session, "evt_bad_price")
    assert Accounts.get_user(user.id).credits == user.credits
  end

  test "refund_stripe_checkout/2 deducts original credits when balance can cover refund" do
    user = user_fixture()

    {session, _attempt} = stripe_paid_session_for(user, "cs_test_refund", "pi_test_refund")

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

  test "refund_stripe_checkout/2 deducts credits once for concurrent full refund events" do
    user = user_fixture()

    {session, _attempt} =
      stripe_paid_session_for(user, "cs_test_concurrent_refund", "pi_test_concurrent_refund")

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_concurrent_checkout")
    assert Accounts.get_user(user.id).credits == user.credits + 50

    refund_event = fn event_id ->
      %{
        "id" => event_id,
        "type" => "charge.refunded",
        "data" => %{
          "object" => %{
            "id" => "ch_test_concurrent_refund",
            "payment_intent" => "pi_test_concurrent_refund"
          }
        }
      }
    end

    results =
      ["evt_stripe_concurrent_refund_1", "evt_stripe_concurrent_refund_2"]
      |> Task.async_stream(
        fn event_id ->
          Payments.refund_stripe_checkout(refund_event.(event_id), event_id)
        end,
        max_concurrency: 2,
        timeout: 5_000
      )
      |> Enum.to_list()

    assert results == [ok: :ok, ok: :ok]
    assert Accounts.get_user(user.id).credits == user.credits

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_concurrent_refund")
    assert payment.refund_status == "refunded"
    assert payment.refund_event_id in ["evt_stripe_concurrent_refund_1", "evt_stripe_concurrent_refund_2"]
  end

  test "refund_stripe_checkout/2 marks review required when balance is too low" do
    user = user_fixture()

    {session, _attempt} =
      stripe_paid_session_for(user, "cs_test_low_balance_refund", "pi_test_low_balance_refund")

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

  test "refund_stripe_checkout/2 marks partial refunds for manual review" do
    user = user_fixture()

    {session, _attempt} =
      stripe_paid_session_for(user, "cs_test_partial_refund", "pi_test_partial_refund")

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_partial_checkout")

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_partial_refund")
    assert Accounts.get_user(user.id).credits == user.credits + payment.credits

    refund_event = %{
      "id" => "evt_stripe_partial_refund",
      "type" => "charge.refunded",
      "data" => %{
        "object" => %{
          "id" => "ch_test_partial_refund",
          "payment_intent" => "pi_test_partial_refund",
          "amount" => payment.amount,
          "amount_refunded" => div(payment.amount, 2)
        }
      }
    }

    assert :ok = Payments.refund_stripe_checkout(refund_event, refund_event["id"])
    assert Accounts.get_user(user.id).credits == user.credits + payment.credits

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_partial_refund")
    assert payment.refund_status == "partial_refund_review"
    assert payment.refund_event_id == "evt_stripe_partial_refund"
    assert payment.refunded_at
  end

  test "refund_stripe_checkout/2 marks partial refunds with expanded payment intent for review" do
    user = user_fixture()

    {session, _attempt} =
      stripe_paid_session_for(user, "cs_test_partial_expanded_refund", "pi_test_partial_expanded_refund")

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_partial_expanded_checkout")

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_partial_expanded_refund")
    assert Accounts.get_user(user.id).credits == user.credits + payment.credits

    refund_event = %{
      "id" => "evt_stripe_partial_expanded_refund",
      "type" => "charge.refunded",
      "data" => %{
        "object" => %{
          "id" => "ch_test_partial_expanded_refund",
          "payment_intent" => %{"id" => "pi_test_partial_expanded_refund"},
          "amount" => payment.amount,
          "amount_refunded" => div(payment.amount, 2)
        }
      }
    }

    assert :ok = Payments.refund_stripe_checkout(refund_event, refund_event["id"])
    assert Accounts.get_user(user.id).credits == user.credits + payment.credits

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_partial_expanded_refund")
    assert payment.refund_status == "partial_refund_review"
    assert payment.refund_event_id == "evt_stripe_partial_expanded_refund"
    assert payment.refunded_at
  end

  test "refund_stripe_checkout/2 partial refund does not overwrite a concurrent full refund" do
    user = user_fixture()

    {session, _attempt} =
      stripe_paid_session_for(user, "cs_test_concurrent_partial_full", "pi_test_concurrent_partial_full")

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_concurrent_partial_full_checkout")

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_concurrent_partial_full")
    parent = self()

    refunded_at = DateTime.utc_now() |> DateTime.truncate(:second)

    partial_refund_event = %{
      "id" => "evt_stripe_concurrent_partial_refund",
      "type" => "charge.refunded",
      "data" => %{
        "object" => %{
          "id" => "ch_test_concurrent_partial_full",
          "payment_intent" => "pi_test_concurrent_partial_full",
          "amount" => payment.amount,
          "amount_refunded" => div(payment.amount, 2)
        }
      }
    }

    locker =
      Task.async(fn ->
        Repo.transaction(fn ->
          from(p in PaymentEvent, where: p.id == ^payment.id, lock: "FOR UPDATE")
          |> Repo.one!()

          from(p in PaymentEvent, where: p.id == ^payment.id)
          |> Repo.update_all(
            set: [
              refunded_at: refunded_at,
              refund_event_id: "evt_stripe_concurrent_full_refund",
              refund_status: "refunded"
            ]
          )

          send(parent, :full_refund_written)

          receive do
            :commit_full_refund -> :ok
          after
            5_000 -> flunk("timed out waiting to commit full refund")
          end
        end)
      end)

    assert_receive :full_refund_written

    partial =
      Task.async(fn ->
        Payments.refund_stripe_checkout(partial_refund_event, partial_refund_event["id"])
      end)

    Process.sleep(100)
    send(locker.pid, :commit_full_refund)

    assert {:ok, _changes} = Task.await(locker)
    assert :ok = Task.await(partial)

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_concurrent_partial_full")
    assert payment.refund_status == "refunded"
    assert payment.refund_event_id == "evt_stripe_concurrent_full_refund"
    assert payment.refunded_at == refunded_at
  end

  test "refund_stripe_checkout/2 applies full refund after partial refund review" do
    user = user_fixture()

    {session, _attempt} =
      stripe_paid_session_for(user, "cs_test_partial_then_full_refund", "pi_test_partial_then_full_refund")

    assert :ok = Payments.fulfill_checkout(session, "evt_stripe_partial_then_full_checkout")

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_partial_then_full_refund")
    assert Accounts.get_user(user.id).credits == user.credits + payment.credits

    partial_refund_event = %{
      "id" => "evt_stripe_partial_then_full_partial_refund",
      "type" => "charge.refunded",
      "data" => %{
        "object" => %{
          "id" => "ch_test_partial_then_full_refund",
          "payment_intent" => "pi_test_partial_then_full_refund",
          "amount" => payment.amount,
          "amount_refunded" => div(payment.amount, 2)
        }
      }
    }

    assert :ok = Payments.refund_stripe_checkout(partial_refund_event, partial_refund_event["id"])
    assert Accounts.get_user(user.id).credits == user.credits + payment.credits

    full_refund_event = %{
      "id" => "evt_stripe_partial_then_full_full_refund",
      "type" => "charge.refunded",
      "data" => %{
        "object" => %{
          "id" => "ch_test_partial_then_full_refund",
          "payment_intent" => "pi_test_partial_then_full_refund",
          "amount" => payment.amount,
          "amount_refunded" => payment.amount
        }
      }
    }

    assert :ok = Payments.refund_stripe_checkout(full_refund_event, full_refund_event["id"])
    assert Accounts.get_user(user.id).credits == user.credits

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_test_partial_then_full_refund")
    assert payment.refund_status == "refunded"
    assert payment.refund_event_id == "evt_stripe_partial_then_full_full_refund"
    assert payment.refunded_at
  end

  test "fulfill_creem_checkout/2 adds credits and records provider" do
    user = user_fixture()

    event = %{
      "id" => "evt_creem_123",
      "eventType" => "checkout.completed",
      "object" => %{
        "id" => "ch_creem_123",
        "order" => "ord_creem_123",
        "metadata" => %{
          "user_id" => Integer.to_string(user.id),
          "credits" => "50",
          "plan" => "starter"
        }
      }
    }

    assert :ok = Payments.fulfill_creem_checkout(event, event["id"])
    assert Accounts.get_user(user.id).credits == user.credits + 50

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "ch_creem_123")
    assert payment.provider == "creem"
    assert payment.provider_order_id == "ord_creem_123"
    assert payment.stripe_event_id == "evt_creem_123"
    assert payment.credits == 50
    assert payment.plan == "starter"
  end

  test "refund_creem_checkout/2 deducts original credits when balance can cover refund" do
    user = user_fixture()

    checkout_event = %{
      "id" => "evt_creem_checkout",
      "eventType" => "checkout.completed",
      "object" => %{
        "id" => "ch_creem_refund",
        "order" => "ord_creem_refund",
        "metadata" => %{
          "user_id" => Integer.to_string(user.id),
          "credits" => "50",
          "plan" => "starter"
        }
      }
    }

    assert :ok = Payments.fulfill_creem_checkout(checkout_event, checkout_event["id"])
    assert Accounts.get_user(user.id).credits == user.credits + 50

    refund_event = %{
      "id" => "evt_creem_refund",
      "eventType" => "refund.created",
      "object" => %{
        "id" => "ref_creem_123",
        "order" => "ord_creem_refund"
      }
    }

    assert :ok = Payments.refund_creem_checkout(refund_event, refund_event["id"])
    assert Accounts.get_user(user.id).credits == user.credits

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "ch_creem_refund")
    assert payment.refund_event_id == "evt_creem_refund"
    assert payment.refunded_at
    assert payment.refund_status == "refunded"

    assert :ok = Payments.refund_creem_checkout(refund_event, refund_event["id"])
    assert Accounts.get_user(user.id).credits == user.credits
  end

  test "refund_creem_checkout/2 marks review required when balance is too low" do
    user = user_fixture()

    checkout_event = %{
      "id" => "evt_creem_low_balance_checkout",
      "eventType" => "checkout.completed",
      "object" => %{
        "id" => "ch_creem_low_balance",
        "order" => "ord_creem_low_balance",
        "metadata" => %{
          "user_id" => Integer.to_string(user.id),
          "credits" => "50",
          "plan" => "starter"
        }
      }
    }

    assert :ok = Payments.fulfill_creem_checkout(checkout_event, checkout_event["id"])

    {:ok, user_after_spend} = Accounts.deduct_credits(user.id, user.credits + 30)
    assert user_after_spend.credits == 20

    refund_event = %{
      "id" => "evt_creem_low_balance_refund",
      "eventType" => "refund.created",
      "object" => %{
        "id" => "ref_creem_low_balance",
        "transaction" => %{"order" => "ord_creem_low_balance"}
      }
    }

    assert :ok = Payments.refund_creem_checkout(refund_event, refund_event["id"])
    assert Accounts.get_user(user.id).credits == 20

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "ch_creem_low_balance")
    assert payment.refund_event_id == "evt_creem_low_balance_refund"
    assert payment.refunded_at
    assert payment.refund_status == "review_required"
  end

  test "record_webhook_event/1 treats only terminal statuses as duplicates" do
    assert {:ok, %PaymentWebhookEvent{} = event} =
             Payments.record_webhook_event(%{
               "id" => "evt_once",
               "type" => "checkout.session.completed",
               "livemode" => false
             })

    assert event.stripe_event_id == "evt_once"
    assert event.event_type == "checkout.session.completed"
    assert event.status == "received"

    assert {:ok, %PaymentWebhookEvent{} = retryable} =
             Payments.record_webhook_event(%{
               "id" => "evt_once",
               "type" => "checkout.session.completed",
               "livemode" => false
             })

    assert retryable.id == event.id

    assert {:ok, %PaymentWebhookEvent{}} = Payments.mark_webhook_event_processed(event)

    assert {:error, :duplicate_event} =
             Payments.record_webhook_event(%{
               "id" => "evt_once",
               "type" => "checkout.session.completed",
               "livemode" => false
             })
  end

  test "record_webhook_event/1 returns existing failed events for retry" do
    assert {:ok, %PaymentWebhookEvent{} = event} =
             Payments.record_webhook_event(%{
               "id" => "evt_failed_retry",
               "type" => "checkout.session.completed",
               "livemode" => false
             })

    assert {:ok, %PaymentWebhookEvent{} = failed_event} =
             Payments.mark_webhook_event_failed(event, :boom)

    assert failed_event.status == "failed"
    assert failed_event.error_reason == "boom"

    assert {:ok, %PaymentWebhookEvent{} = retryable} =
             Payments.record_webhook_event(%{
               "id" => "evt_failed_retry",
               "type" => "checkout.session.completed",
               "livemode" => false
             })

    assert retryable.id == event.id
    assert retryable.status == "failed"
  end

  test "record_webhook_event/1 treats ignored events as duplicates" do
    assert {:ok, %PaymentWebhookEvent{} = event} =
             Payments.record_webhook_event(%{
               "id" => "evt_ignored_duplicate",
               "type" => "checkout.session.completed",
               "livemode" => false
             })

    assert {:ok, %PaymentWebhookEvent{}} = Payments.mark_webhook_event_ignored(event)

    assert {:error, :duplicate_event} =
             Payments.record_webhook_event(%{
               "id" => "evt_ignored_duplicate",
               "type" => "checkout.session.completed",
               "livemode" => false
             })
  end

  test "record_webhook_event/1 rejects malformed events" do
    assert {:error, :invalid_event} = Payments.record_webhook_event(%{"id" => "evt_missing_type"})
    assert {:error, :invalid_event} = Payments.record_webhook_event(%{"type" => "checkout.session.completed"})
    assert {:error, :invalid_event} = Payments.record_webhook_event(%{})
  end

  test "verify_creem_webhook/2 validates HMAC signature" do
    secret = System.get_env("CREEM_WEBHOOK_SECRET")

    on_exit(fn ->
      restore_env("CREEM_WEBHOOK_SECRET", secret)
    end)

    System.put_env("CREEM_WEBHOOK_SECRET", "whsec_test")
    payload = ~s({"eventType":"checkout.completed"})

    signature =
      :crypto.mac(:hmac, :sha256, "whsec_test", payload)
      |> Base.encode16(case: :lower)

    assert {:ok, %{"eventType" => "checkout.completed"}} =
             Payments.verify_creem_webhook(payload, signature)

    assert {:error, :invalid_signature} = Payments.verify_creem_webhook(payload, "bad")
  end

  test "verify_webhook/2 validates Stripe signed payloads" do
    secret = System.get_env("STRIPE_WEBHOOK_SECRET")

    on_exit(fn ->
      restore_env("STRIPE_WEBHOOK_SECRET", secret)
    end)

    System.put_env("STRIPE_WEBHOOK_SECRET", "whsec_stripe_test")
    payload = ~s({"type":"checkout.session.completed"})
    timestamp = Integer.to_string(System.system_time(:second))
    signature = stripe_signature(payload, timestamp)

    assert {:ok, %{"type" => "checkout.session.completed"}} =
             Payments.verify_webhook(payload, signature)

    assert {:error, :invalid_signature} =
             Payments.verify_webhook(payload, "t=#{timestamp},v1=bad")
  end

  test "verify_webhook/2 accepts any matching Stripe v1 signature" do
    secret = System.get_env("STRIPE_WEBHOOK_SECRET")

    on_exit(fn ->
      restore_env("STRIPE_WEBHOOK_SECRET", secret)
    end)

    System.put_env("STRIPE_WEBHOOK_SECRET", "whsec_stripe_test")
    payload = ~s({"type":"checkout.session.completed"})
    timestamp = Integer.to_string(System.system_time(:second))
    "t=" <> timestamp_and_signature = stripe_signature(payload, timestamp)
    [_timestamp, valid_signature] = String.split(timestamp_and_signature, ",", parts: 2)

    assert {:ok, %{"type" => "checkout.session.completed"}} =
             Payments.verify_webhook(payload, "t=#{timestamp},v1=bad,#{valid_signature}")
  end

  test "verify_webhook/2 enforces Stripe timestamp tolerance boundary" do
    secret = System.get_env("STRIPE_WEBHOOK_SECRET")
    System.put_env("STRIPE_WEBHOOK_SECRET", "whsec_stripe_test")

    on_exit(fn -> restore_env("STRIPE_WEBHOOK_SECRET", secret) end)

    now = System.system_time(:second)
    payload = ~s({"type":"checkout.session.completed"})

    assert {:ok, %{"type" => "checkout.session.completed"}} =
             Payments.verify_webhook(payload, stripe_signature(payload, now - 300))

    assert {:error, :invalid_signature} =
             Payments.verify_webhook(payload, stripe_signature(payload, now - 301))

    assert {:ok, %{"type" => "checkout.session.completed"}} =
             Payments.verify_webhook(payload, stripe_signature(payload, now + 300))

    assert {:error, :invalid_signature} =
             Payments.verify_webhook(payload, stripe_signature(payload, now + 301))
  end

  defp start_stripe_checkout_stub(response_body) do
    parent = self()
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])
    {:ok, port} = :inet.port(listen_socket)

    spawn_link(fn ->
      case :gen_tcp.accept(listen_socket, 2_000) do
        {:ok, socket} ->
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

        {:error, _reason} ->
          :gen_tcp.close(listen_socket)
      end
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

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp stripe_paid_session_for(user, session_id, payment_intent, plan_id \\ "starter") do
    plan = Payments.get_plan(plan_id)
    {:ok, %PaymentAttempt{} = attempt} = Payments.create_payment_attempt(plan, user)

    {:ok, %PaymentAttempt{} = attempt} =
      Payments.mark_payment_attempt_open(attempt, %{
        "id" => session_id,
        "payment_intent" => payment_intent
      })

    {%{
       "id" => session_id,
       "mode" => "payment",
       "payment_status" => "paid",
       "payment_intent" => payment_intent,
       "amount_total" => plan.amount,
       "currency" => plan.currency,
       "metadata" => %{
         "user_id" => Integer.to_string(user.id),
         "credits" => Integer.to_string(plan.credits),
         "plan" => plan.id,
         "payment_attempt_id" => Integer.to_string(attempt.id)
       }
     }, attempt}
  end

  defp stripe_signature(payload, timestamp) when is_integer(timestamp) do
    stripe_signature(payload, Integer.to_string(timestamp))
  end

  defp stripe_signature(payload, timestamp) do
    digest =
      :crypto.mac(:hmac, :sha256, "whsec_stripe_test", "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{digest}"
  end
end
