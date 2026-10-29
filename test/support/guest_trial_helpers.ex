defmodule Sticker.GuestTrialHelpers do
  @moduledoc false

  alias Sticker.GuestTrials
  alias Sticker.GuestTrials.GuestTrialCredit
  alias Sticker.Repo

  @doc """
  Seeds a guest allowance with spendable credits (legacy-style balance).
  New guests otherwise start at 0 under the current product rules.
  """
  def seed_guest_credits(local_user_id, remaining \\ 3)
      when is_binary(local_user_id) and is_integer(remaining) and remaining >= 0 do
    {:ok, allowance} = GuestTrials.get_or_create_allowance(local_user_id)

    allowance
    |> GuestTrialCredit.changeset(%{
      credits_remaining: remaining,
      credits_spent: 0,
      credits_refunded: 0
    })
    |> Repo.update!()
  end
end
