defmodule Sticker.GuestTrials.GuestTrialCredit do
  use Ecto.Schema
  import Ecto.Changeset

  @max_trial_credits 3

  schema "guest_trial_credits" do
    field :local_user_id, :string
    field :credits_remaining, :integer, default: @max_trial_credits
    field :credits_spent, :integer, default: 0
    field :credits_refunded, :integer, default: 0
    field :last_seen_at, :utc_datetime

    timestamps()
  end

  def changeset(guest_trial_credit, attrs) do
    guest_trial_credit
    |> cast(attrs, [
      :local_user_id,
      :credits_remaining,
      :credits_spent,
      :credits_refunded,
      :last_seen_at
    ])
    |> validate_required([:local_user_id, :credits_remaining, :credits_spent, :credits_refunded])
    |> validate_format(:local_user_id, ~r/^[A-Za-z0-9_-]+$/)
    |> validate_length(:local_user_id, min: 6, max: 128)
    |> validate_number(:credits_remaining,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @max_trial_credits
    )
    |> validate_number(:credits_spent, greater_than_or_equal_to: 0)
    |> validate_number(:credits_refunded, greater_than_or_equal_to: 0)
    |> unique_constraint(:local_user_id)
    |> check_constraint(:credits_remaining, name: :guest_trial_credits_remaining_range)
    |> check_constraint(:credits_spent, name: :guest_trial_credits_spent_non_negative)
    |> check_constraint(:credits_refunded, name: :guest_trial_credits_refunded_non_negative)
  end
end
