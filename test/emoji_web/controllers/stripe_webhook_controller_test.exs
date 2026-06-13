defmodule StickerWeb.StripeWebhookControllerTest do
  use StickerWeb.ConnCase

  alias Sticker.Accounts
  alias Sticker.Payments
  alias Sticker.Payments.PaymentAttempt
  alias Sticker.Payments.PaymentEvent
  alias Sticker.Payments.PaymentWebhookEvent
  alias Sticker.Repo

  import Ecto.Query
  import Sticker.AccountsFixtures

  test "POST /webhooks/stripe handles charge.refunded events", %{conn: conn} do
    old_starter = System.get_env("STRIPE_STARTER_PRICE_ID")
    System.put_env("STRIPE_STARTER_PRICE_ID", "price_starter_controller_test")

    on_exit(fn -> restore_env("STRIPE_STARTER_PRICE_ID", old_starter) end)

    user = user_fixture()
    session = stripe_paid_session_for(user, "cs_controller_refund", "pi_controller_refund")

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
      |> put_req_header("stripe-signature", "t=#{System.system_time(:second)},v1=bad")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 400) == "bad request"
  end

  test "POST /webhooks/stripe processes checkout.session.completed events", %{conn: conn} do
    old_starter = System.get_env("STRIPE_STARTER_PRICE_ID")
    System.put_env("STRIPE_STARTER_PRICE_ID", "price_starter_controller_test")

    on_exit(fn -> restore_env("STRIPE_STARTER_PRICE_ID", old_starter) end)

    user = user_fixture()
    session = stripe_paid_session_for(user, "cs_controller_checkout", "pi_controller_checkout")

    payload =
      Jason.encode!(%{
        "id" => "evt_controller_checkout_completed",
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => session
        }
      })

    conn =
      conn
      |> put_req_header("stripe-signature", stripe_signature(payload))
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 200) == "ok"
    assert Accounts.get_user(user.id).credits == user.credits + 50

    webhook_event =
      Repo.get_by!(PaymentWebhookEvent, stripe_event_id: "evt_controller_checkout_completed")

    assert webhook_event.status == "processed"
  end

  test "POST /webhooks/stripe marks terminal checkout business errors failed but returns 200", %{
    conn: conn
  } do
    payload =
      Jason.encode!(%{
        "id" => "evt_invalid_checkout_controller",
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "id" => "cs_invalid_checkout_controller",
            "mode" => "payment",
            "payment_status" => "paid"
          }
        }
      })

    conn =
      conn
      |> put_req_header("stripe-signature", stripe_signature(payload))
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 200) == "ok"

    webhook_event =
      Repo.get_by!(PaymentWebhookEvent, stripe_event_id: "evt_invalid_checkout_controller")

    assert webhook_event.status == "failed"
    assert webhook_event.error_reason == "invalid_checkout_metadata"
  end

  test "POST /webhooks/stripe retries failed webhook events and marks them processed", %{conn: conn} do
    old_starter = System.get_env("STRIPE_STARTER_PRICE_ID")
    System.put_env("STRIPE_STARTER_PRICE_ID", "price_starter_controller_test")

    on_exit(fn -> restore_env("STRIPE_STARTER_PRICE_ID", old_starter) end)

    user = user_fixture()
    session = stripe_paid_session_for(user, "cs_retry_after_failed", "pi_retry_after_failed")

    payload_map = %{
      "id" => "evt_retry_after_failed",
      "type" => "checkout.session.completed",
      "data" => %{
        "object" => session
      }
    }

    assert {:ok, %PaymentWebhookEvent{} = webhook_event} =
             Payments.record_webhook_event(payload_map)

    assert {:ok, %PaymentWebhookEvent{}} =
             Payments.mark_webhook_event_failed(webhook_event, :transient_error)

    payload = Jason.encode!(payload_map)

    conn =
      conn
      |> put_req_header("stripe-signature", stripe_signature(payload))
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 200) == "ok"
    assert Accounts.get_user(user.id).credits == user.credits + 50

    webhook_event = Repo.get_by!(PaymentWebhookEvent, stripe_event_id: "evt_retry_after_failed")
    assert webhook_event.status == "processed"
  end

  test "POST /webhooks/stripe returns 500 for unknown business failures after marking failed", %{
    conn: conn
  } do
    old_starter = System.get_env("STRIPE_STARTER_PRICE_ID")
    System.put_env("STRIPE_STARTER_PRICE_ID", "price_starter_controller_test")

    on_exit(fn -> restore_env("STRIPE_STARTER_PRICE_ID", old_starter) end)

    user = user_fixture()

    session =
      stripe_paid_session_for(
        user,
        "cs_unknown_failure_controller",
        "pi_unknown_failure_controller"
      )

    assert :ok = Payments.fulfill_checkout(session, "evt_unknown_failure_checkout")

    payment = Repo.get_by!(PaymentEvent, stripe_session_id: "cs_unknown_failure_controller")

    payment
    |> PaymentEvent.changeset(%{provider_order_id: "pi_tampered_controller"})
    |> Repo.update!()

    payload =
      Jason.encode!(%{
        "id" => "evt_unknown_failure_controller",
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => session
        }
      })

    conn =
      conn
      |> put_req_header("stripe-signature", stripe_signature(payload))
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 500) == "error"

    webhook_event =
      Repo.get_by!(PaymentWebhookEvent, stripe_event_id: "evt_unknown_failure_controller")

    assert webhook_event.status == "failed"
    assert webhook_event.error_reason == "duplicate_checkout_mismatch"
  end

  test "POST /webhooks/stripe does not re-credit duplicate checkout events", %{conn: conn} do
    old_starter = System.get_env("STRIPE_STARTER_PRICE_ID")
    System.put_env("STRIPE_STARTER_PRICE_ID", "price_starter_controller_test")

    on_exit(fn -> restore_env("STRIPE_STARTER_PRICE_ID", old_starter) end)

    user = user_fixture()
    session = stripe_paid_session_for(user, "cs_duplicate_controller", "pi_duplicate_controller")

    payload =
      Jason.encode!(%{
        "id" => "evt_duplicate_webhook",
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => session
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

    assert [_payment] =
             Repo.all(
               from e in PaymentEvent,
                 where: e.stripe_session_id == "cs_duplicate_controller"
             )
  end

  test "POST /webhooks/stripe accepts signed unsupported events and marks them ignored", %{conn: conn} do
    payload =
      Jason.encode!(%{
        "id" => "evt_ignored_controller",
        "type" => "customer.created",
        "data" => %{"object" => %{"id" => "cus_controller"}}
      })

    conn =
      conn
      |> put_req_header("stripe-signature", stripe_signature(payload))
      |> put_req_header("content-type", "application/json")
      |> post(~p"/webhooks/stripe", payload)

    assert response(conn, 200) == "ok"

    webhook_event = Repo.get_by!(PaymentWebhookEvent, stripe_event_id: "evt_ignored_controller")
    assert webhook_event.status == "ignored"

    assert {:error, :duplicate_event} =
             Payments.record_webhook_event(%{
               "id" => "evt_ignored_controller",
               "type" => "customer.created"
             })
  end

  defp stripe_signature(payload) do
    secret = System.get_env("STRIPE_WEBHOOK_SECRET")

    on_exit(fn ->
      restore_env("STRIPE_WEBHOOK_SECRET", secret)
    end)

    System.put_env("STRIPE_WEBHOOK_SECRET", "whsec_controller_test")
    timestamp = Integer.to_string(System.system_time(:second))

    digest =
      :crypto.mac(:hmac, :sha256, "whsec_controller_test", "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{digest}"
  end

  defp stripe_paid_session_for(user, session_id, payment_intent) do
    plan = Payments.get_plan("starter")
    {:ok, %PaymentAttempt{} = attempt} = Payments.create_payment_attempt(plan, user)

    {:ok, %PaymentAttempt{} = attempt} =
      Payments.mark_payment_attempt_open(attempt, %{
        "id" => session_id,
        "payment_intent" => payment_intent
      })

    %{
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
    }
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
