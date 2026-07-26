defmodule Sticker.Repo.Migrations.CreateGuestGenerationAttempts do
  use Ecto.Migration

  def change do
    create table(:guest_generation_attempts) do
      add :request_id, :uuid, null: false
      add :guest_user_id, :string, null: false
      add :ip_hash, :string, size: 64, null: false
      add :mode, :string, null: false
      add :task_count, :integer, null: false
      add :turnstile_required, :boolean, null: false, default: false
      add :turnstile_verified, :boolean, null: false, default: false
      add :risk_reason, :string, size: 64

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create unique_index(:guest_generation_attempts, [:request_id])
    create index(:guest_generation_attempts, [:ip_hash, :inserted_at])
    create index(:guest_generation_attempts, [:guest_user_id, :inserted_at])

    create constraint(:guest_generation_attempts, :guest_attempt_task_count,
             check: "task_count BETWEEN 1 AND 5"
           )

    create constraint(:guest_generation_attempts, :guest_attempt_mode,
             check: "mode IN ('text', 'portrait')"
           )

    create constraint(:guest_generation_attempts, :guest_attempt_ip_hash,
             check: "ip_hash ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:guest_generation_attempts, :guest_attempt_guest_user_id,
             check: "guest_user_id ~ '^[A-Za-z0-9_-]{6,128}$'"
           )
  end
end
