defmodule Sticker.PaymentsTest do
  use Sticker.DataCase

  alias Sticker.Accounts
  alias Sticker.Payments
  alias Sticker.Payments.PaymentEvent
  alias Sticker.Repo

  import Sticker.AccountsFixtures

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

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
