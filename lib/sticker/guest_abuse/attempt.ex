defmodule Sticker.GuestAbuse.Attempt do
  use Ecto.Schema
  import Ecto.Changeset

  schema "guest_generation_attempts" do
    field :request_id, Ecto.UUID
    field :guest_user_id, :string
    field :ip_hash, :string
    field :mode, :string
    field :task_count, :integer
    field :turnstile_required, :boolean, default: false
    field :turnstile_verified, :boolean, default: false
    field :risk_reason, :string

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :request_id,
      :guest_user_id,
      :ip_hash,
      :mode,
      :task_count,
      :turnstile_required,
      :turnstile_verified,
      :risk_reason
    ])
    |> validate_required([
      :request_id,
      :guest_user_id,
      :ip_hash,
      :mode,
      :task_count,
      :turnstile_required,
      :turnstile_verified
    ])
    |> validate_format(:guest_user_id, ~r/^[A-Za-z0-9_-]+$/)
    |> validate_length(:guest_user_id, min: 6, max: 128)
    |> validate_format(:ip_hash, ~r/^[0-9a-f]{64}$/)
    |> validate_inclusion(:mode, ["text", "portrait"])
    |> validate_number(:task_count, greater_than: 0, less_than_or_equal_to: 5)
    |> validate_length(:risk_reason, max: 64)
    |> unique_constraint(:request_id)
    |> check_constraint(:task_count, name: :guest_attempt_task_count)
    |> check_constraint(:mode, name: :guest_attempt_mode)
    |> check_constraint(:ip_hash, name: :guest_attempt_ip_hash)
    |> check_constraint(:guest_user_id, name: :guest_attempt_guest_user_id)
  end
end
