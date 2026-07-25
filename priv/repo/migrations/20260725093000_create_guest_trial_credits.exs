defmodule Sticker.Repo.Migrations.CreateGuestTrialCredits do
  use Ecto.Migration

  def change do
    create table(:guest_trial_credits) do
      add :local_user_id, :string, null: false
      add :credits_remaining, :integer, null: false, default: 3
      add :credits_spent, :integer, null: false, default: 0
      add :credits_refunded, :integer, null: false, default: 0
      add :last_seen_at, :utc_datetime

      timestamps()
    end

    create unique_index(:guest_trial_credits, [:local_user_id])

    create constraint(:guest_trial_credits, :guest_trial_credits_remaining_range,
             check: "credits_remaining >= 0 AND credits_remaining <= 3"
           )

    create constraint(:guest_trial_credits, :guest_trial_credits_spent_non_negative,
             check: "credits_spent >= 0"
           )

    create constraint(:guest_trial_credits, :guest_trial_credits_refunded_non_negative,
             check: "credits_refunded >= 0"
           )
  end
end
