defmodule Sticker.GuestAbuseTest do
  use Sticker.DataCase

  alias Sticker.GuestAbuse
  alias Sticker.GuestAbuse.Attempt
  alias Sticker.Repo

  setup do
    previous_secret = Application.get_env(:sticker, :guest_ip_hash_secret)
    Application.put_env(:sticker, :guest_ip_hash_secret, "test-guest-ip-hash-secret")

    on_exit(fn ->
      if previous_secret do
        Application.put_env(:sticker, :guest_ip_hash_secret, previous_secret)
      else
        Application.delete_env(:sticker, :guest_ip_hash_secret)
      end
    end)

    :ok
  end

  test "IP hashing is deterministic and never stores the raw address" do
    hash = GuestAbuse.ip_hash("203.0.113.10")

    assert hash == GuestAbuse.ip_hash("203.0.113.10")
    assert byte_size(hash) == 64
    assert hash =~ ~r/^[0-9a-f]{64}$/
    refute hash =~ "203.0.113.10"
  end

  test "reserves six rolling tasks and rejects the seventh" do
    now = ~U[2026-07-26 01:00:00.000000Z]
    ip_hash = GuestAbuse.ip_hash("203.0.113.11")

    for index <- 1..6 do
      assert {:ok, %Attempt{}} =
               GuestAbuse.reserve_attempt(attempt_attrs(ip_hash, index), now)
    end

    assert {:error, :guest_ip_limited} =
             GuestAbuse.reserve_attempt(attempt_attrs(ip_hash, 7), now)

    assert Repo.aggregate(Attempt, :count) == 6
  end

  test "batch reservation is atomic and duplicate request IDs do not count twice" do
    now = ~U[2026-07-26 01:00:00.000000Z]
    ip_hash = GuestAbuse.ip_hash("203.0.113.12")
    attrs = attempt_attrs(ip_hash, 1, task_count: 3)

    assert {:ok, %Attempt{task_count: 3}} = GuestAbuse.reserve_attempt(attrs, now)
    assert {:error, :attempt_duplicate} = GuestAbuse.reserve_attempt(attrs, now)

    assert {:ok, %Attempt{task_count: 3}} =
             GuestAbuse.reserve_attempt(attempt_attrs(ip_hash, 2, task_count: 3), now)

    assert {:error, :guest_ip_limited} =
             GuestAbuse.reserve_attempt(attempt_attrs(ip_hash, 3), now)

    assert Repo.aggregate(Attempt, :count) == 2
  end

  test "risk snapshot counts recent tasks and distinct guest identities" do
    now = ~U[2026-07-26 01:00:00.000000Z]
    ip_hash = GuestAbuse.ip_hash("203.0.113.13")

    assert {:ok, _attempt} =
             GuestAbuse.reserve_attempt(
               attempt_attrs(ip_hash, 1, guest_user_id: "gst_guest_one", task_count: 2),
               DateTime.add(now, -9, :minute)
             )

    assert {:ok, _attempt} =
             GuestAbuse.reserve_attempt(
               attempt_attrs(ip_hash, 2, guest_user_id: "gst_guest_two"),
               DateTime.add(now, -1, :minute)
             )

    assert %{task_count: 3, distinct_guest_count: 2} = GuestAbuse.risk_snapshot(ip_hash, now)
  end

  test "rolling windows exclude records exactly on the ten-minute and 24-hour boundaries" do
    now = ~U[2026-07-26 01:00:00.000000Z]
    ip_hash = GuestAbuse.ip_hash("203.0.113.14")

    assert {:ok, _attempt} =
             GuestAbuse.reserve_attempt(
               attempt_attrs(ip_hash, 1, task_count: 5),
               DateTime.add(now, -24, :hour)
             )

    assert {:ok, _attempt} =
             GuestAbuse.reserve_attempt(
               attempt_attrs(ip_hash, 2),
               DateTime.add(now, -10, :minute)
             )

    assert %{task_count: 0, distinct_guest_count: 0} = GuestAbuse.risk_snapshot(ip_hash, now)

    assert {:ok, %Attempt{task_count: 5}} =
             GuestAbuse.reserve_attempt(attempt_attrs(ip_hash, 3, task_count: 5), now)
  end

  test "concurrent reservations cannot exceed six model tasks" do
    now = ~U[2026-07-26 01:00:00.000000Z]
    ip_hash = GuestAbuse.ip_hash("203.0.113.15")

    results =
      1..8
      |> Enum.map(fn index ->
        Task.async(fn -> GuestAbuse.reserve_attempt(attempt_attrs(ip_hash, index), now) end)
      end)
      |> Task.await_many(5_000)

    assert Enum.count(results, &match?({:ok, %Attempt{}}, &1)) == 6
    assert Enum.count(results, &match?({:error, :guest_ip_limited}, &1)) == 2

    assert Repo.aggregate(Attempt, :sum, :task_count) == 6
  end

  test "attempt changeset rejects invalid mode, task count, UUID, guest ID, and hash" do
    changeset =
      Attempt.changeset(%Attempt{}, %{
        request_id: "not-a-uuid",
        guest_user_id: "bad",
        ip_hash: "raw-ip",
        mode: "other",
        task_count: 6,
        turnstile_required: nil,
        turnstile_verified: nil
      })

    refute changeset.valid?

    assert errors_on(changeset).request_id
    assert errors_on(changeset).guest_user_id
    assert errors_on(changeset).ip_hash
    assert errors_on(changeset).mode
    assert errors_on(changeset).task_count
    assert errors_on(changeset).turnstile_required
    assert errors_on(changeset).turnstile_verified
  end

  defp attempt_attrs(ip_hash, index, overrides \\ []) do
    request_id = Ecto.UUID.generate()

    %{
      request_id: request_id,
      guest_user_id: "gst_guest_#{index}",
      ip_hash: ip_hash,
      mode: "text",
      task_count: 1,
      turnstile_required: false,
      turnstile_verified: false,
      risk_reason: nil
    }
    |> Map.merge(Map.new(overrides))
  end
end
