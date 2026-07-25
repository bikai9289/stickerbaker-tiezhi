defmodule Sticker.GuestTrialsTest do
  use Sticker.DataCase

  alias Sticker.GuestTrials

  test "get_or_create_allowance/1 creates three guest trial credits" do
    assert {:ok, allowance} = GuestTrials.get_or_create_allowance("guest_trial_one")

    assert allowance.local_user_id == "guest_trial_one"
    assert allowance.credits_remaining == 3
    assert allowance.credits_spent == 0
    assert allowance.credits_refunded == 0
  end

  test "get_or_create_allowance/1 rejects invalid guest identifiers" do
    assert {:error, :invalid_guest_identity} =
             GuestTrials.get_or_create_allowance("bad guest id")
  end

  test "spend_credits/2 deducts atomically and rejects exhausted guests" do
    assert {:ok, allowance} = GuestTrials.spend_credits("guest_spend_one", 2)
    assert allowance.credits_remaining == 1
    assert allowance.credits_spent == 2

    assert {:error, :guest_insufficient_credits} =
             GuestTrials.spend_credits("guest_spend_one", 2)
  end

  test "refund_credits/2 restores a spent credit only once" do
    assert {:ok, allowance} = GuestTrials.spend_credits("guest_refund_one", 1)
    assert allowance.credits_remaining == 2

    assert {:ok, allowance} = GuestTrials.refund_credits("guest_refund_one", 1)
    assert allowance.credits_remaining == 3
    assert allowance.credits_refunded == 1

    assert {:error, :not_refundable} = GuestTrials.refund_credits("guest_refund_one", 1)
  end

  test "concurrent spend attempts cannot overspend the final credit" do
    assert {:ok, _allowance} = GuestTrials.spend_credits("guest_race_one", 2)

    results =
      1..2
      |> Enum.map(fn _index ->
        Task.async(fn -> GuestTrials.spend_credits("guest_race_one", 1) end)
      end)
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _allowance}, &1)) == 1
    assert Enum.count(results, &match?({:error, :guest_insufficient_credits}, &1)) == 1
    assert GuestTrials.get_allowance("guest_race_one").credits_remaining == 0
  end
end
