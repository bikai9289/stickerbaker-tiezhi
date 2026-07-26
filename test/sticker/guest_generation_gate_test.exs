defmodule Sticker.GuestGenerationGateTest do
  use Sticker.DataCase

  alias Sticker.GuestAbuse
  alias Sticker.GuestAbuse.Attempt
  alias Sticker.GuestGenerationGate
  alias Sticker.GuestTrials
  alias Sticker.Repo

  defmodule VerifierStub do
    @behaviour Sticker.Turnstile.Verifier

    @impl true
    def verify(token, remote_ip, request_id) do
      send(Process.get(:gate_test_pid), {:verify, token, remote_ip, request_id})
      Process.get(:gate_verifier_result, :ok)
    end
  end

  setup do
    previous_turnstile = Application.get_env(:sticker, :turnstile)
    previous_verifier = Application.get_env(:sticker, :turnstile_verifier)
    previous_secret = Application.get_env(:sticker, :guest_ip_hash_secret)

    Process.put(:gate_test_pid, self())
    Application.put_env(:sticker, :guest_ip_hash_secret, "test-guest-ip-hash-secret")
    Application.put_env(:sticker, :turnstile, enabled: false)
    Application.put_env(:sticker, :turnstile_verifier, VerifierStub)

    on_exit(fn ->
      restore_env(:turnstile, previous_turnstile)
      restore_env(:turnstile_verifier, previous_verifier)
      restore_env(:guest_ip_hash_secret, previous_secret)
    end)

    :ok
  end

  test "authenticated users bypass all guest checks and create no attempt" do
    assert {:ok, %{authenticated?: true}} =
             GuestGenerationGate.authorize(%{
               current_user: %{id: 1},
               guest_user_id: nil,
               canonical_ip: nil,
               request_id: "bad",
               mode: :text,
               task_count: 99,
               turnstile_token: nil
             })

    assert Repo.aggregate(Attempt, :count) == 0
  end

  test "first low-risk guest request stays frictionless when protection is disabled" do
    attrs = gate_attrs("gst_first_guest", "203.0.113.30")

    assert {:ok, metadata} = GuestGenerationGate.authorize(attrs)
    refute metadata.authenticated?
    refute metadata.challenge_required?
    assert metadata.challenge_reason == nil
    assert Repo.aggregate(Attempt, :count) == 1
    refute_received {:verify, _, _, _}
  end

  test "second guest request requires and verifies Turnstile when enabled" do
    enable_turnstile()
    guest_user_id = "gst_repeat_guest"
    {:ok, _allowance} = GuestTrials.spend_credits(guest_user_id, 1)
    attrs = gate_attrs(guest_user_id, "203.0.113.31")

    assert {:error, :turnstile_required} = GuestGenerationGate.authorize(attrs)
    assert Repo.aggregate(Attempt, :count) == 0

    request_id = attrs.request_id
    attrs = %{attrs | turnstile_token: "valid-token"}

    assert {:ok, %{challenge_required?: true, challenge_reason: :repeat_guest}} =
             GuestGenerationGate.authorize(attrs)

    assert_receive {:verify, "valid-token", "203.0.113.31", ^request_id}
    assert Repo.one!(Attempt).turnstile_verified
  end

  test "three recent tasks or two identities challenge a first request" do
    enable_turnstile()
    now = ~U[2026-07-26 02:00:00.000000Z]
    ip = "203.0.113.32"
    ip_hash = GuestAbuse.ip_hash(ip)

    assert {:ok, _attempt} =
             GuestAbuse.reserve_attempt(attempt_attrs(ip_hash, "gst_risk_one", 2), now)

    assert {:ok, _attempt} =
             GuestAbuse.reserve_attempt(attempt_attrs(ip_hash, "gst_risk_two", 1), now)

    attrs = gate_attrs("gst_new_guest", ip)

    assert {:error, :turnstile_required} = GuestGenerationGate.authorize(attrs, now)

    Process.put(:gate_verifier_result, {:error, :turnstile_expired})

    assert {:error, :turnstile_expired} =
             GuestGenerationGate.authorize(%{attrs | turnstile_token: "expired"}, now)

    assert Repo.aggregate(Attempt, :count) == 2
  end

  test "exhausted credits, IP limit, duplicate, and invalid parameters return dedicated errors" do
    exhausted_guest = "gst_exhausted_guest"
    {:ok, _allowance} = GuestTrials.spend_credits(exhausted_guest, 3)

    assert {:error, :guest_credits_exhausted} =
             GuestGenerationGate.authorize(gate_attrs(exhausted_guest, "203.0.113.33"))

    assert {:error, :guest_identity_missing} =
             GuestGenerationGate.authorize(gate_attrs("bad", "203.0.113.33"))

    attrs = gate_attrs("gst_valid_guest", "203.0.113.34")
    assert {:ok, _metadata} = GuestGenerationGate.authorize(attrs)
    assert {:error, :attempt_duplicate} = GuestGenerationGate.authorize(attrs)

    ip = "203.0.113.35"
    ip_hash = GuestAbuse.ip_hash(ip)
    now = DateTime.utc_now()

    assert {:ok, _attempt} =
             GuestAbuse.reserve_attempt(attempt_attrs(ip_hash, "gst_limit_guest", 5), now)

    assert {:error, :guest_ip_limited} =
             GuestGenerationGate.authorize(
               gate_attrs("gst_other_guest", ip, task_count: 2),
               now
             )
  end

  defp gate_attrs(guest_user_id, canonical_ip, overrides \\ []) do
    %{
      current_user: nil,
      guest_user_id: guest_user_id,
      canonical_ip: canonical_ip,
      request_id: Ecto.UUID.generate(),
      mode: :text,
      task_count: 1,
      turnstile_token: nil
    }
    |> Map.merge(Map.new(overrides))
  end

  defp attempt_attrs(ip_hash, guest_user_id, task_count) do
    %{
      request_id: Ecto.UUID.generate(),
      guest_user_id: guest_user_id,
      ip_hash: ip_hash,
      mode: "text",
      task_count: task_count,
      turnstile_required: false,
      turnstile_verified: false,
      risk_reason: nil
    }
  end

  defp enable_turnstile do
    Application.put_env(:sticker, :turnstile,
      enabled: true,
      site_key: "site-key",
      secret_key: "secret-key"
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:sticker, key)
  defp restore_env(key, value), do: Application.put_env(:sticker, key, value)
end
