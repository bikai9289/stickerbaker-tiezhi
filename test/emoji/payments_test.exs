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
    assert payment.stripe_event_id == "evt_creem_123"
    assert payment.credits == 50
    assert payment.plan == "starter"
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
