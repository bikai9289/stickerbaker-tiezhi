defmodule Sticker.GuestTrialsTest do
  use Sticker.DataCase

  import Sticker.GuestTrialHelpers

  alias Sticker.GuestTrials

  test "get_or_create_allowance/1 creates zero guest trial credits for new guests" do
    assert {:ok, allowance} = GuestTrials.get_or_create_allowance("guest_trial_one")

    assert allowance.local_user_id == "guest_trial_one"
    assert allowance.credits_remaining == 0
    assert allowance.credits_spent == 0
    assert allowance.credits_refunded == 0
  end

  test "get_or_create_allowance/1 rejects invalid guest identifiers" do
    assert {:error, :invalid_guest_identity} =
             GuestTrials.get_or_create_allowance("bad guest id")
  end

  test "spend_credits/2 deducts atomically and rejects exhausted guests" do
    seed_guest_credits("guest_spend_one", 3)

    assert {:ok, allowance} = GuestTrials.spend_credits("guest_spend_one", 2)
    assert allowance.credits_remaining == 1
    assert allowance.credits_spent == 2

    assert {:error, :guest_insufficient_credits} =
             GuestTrials.spend_credits("guest_spend_one", 2)
  end

  test "refund_credits/2 restores a spent credit only once" do
    seed_guest_credits("guest_refund_one", 3)

    assert {:ok, allowance} = GuestTrials.spend_credits("guest_refund_one", 1)
    assert allowance.credits_remaining == 2

    assert {:ok, allowance} = GuestTrials.refund_credits("guest_refund_one", 1)
    assert allowance.credits_remaining == 3
    assert allowance.credits_refunded == 1

    assert {:error, :not_refundable} = GuestTrials.refund_credits("guest_refund_one", 1)
  end

  test "concurrent spend attempts cannot overspend the final credit" do
    seed_guest_credits("guest_race_one", 3)
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

  test "free_credits_for_signup/1 grants remaining when legacy guest has credits" do
    seed_guest_credits("guest_signup_remaining", 2)
    assert GuestTrials.free_credits_for_signup("guest_signup_remaining") == 2
  end

  test "free_credits_for_signup/1 grants signup bonus when guest remaining is 0" do
    seed_guest_credits("guest_signup_zero", 0)
    assert GuestTrials.free_credits_for_signup("guest_signup_zero") == 1
  end

  test "free_credits_for_signup/1 grants signup bonus when no guest row exists" do
    assert GuestTrials.free_credits_for_signup("guest_never_seen") == 1
    assert GuestTrials.free_credits_for_signup(nil) == 1
  end
end
