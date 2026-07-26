defmodule Sticker.GuestAbuse do
  import Ecto.Query

  alias Sticker.GuestAbuse.Attempt
  alias Sticker.Repo

  @daily_limit 6
  @quota_window_seconds 24 * 60 * 60
  @risk_window_seconds 10 * 60

  def ip_hash(canonical_ip) when is_binary(canonical_ip) do
    :crypto.mac(:hmac, :sha256, ip_hash_secret(), canonical_ip)
    |> Base.encode16(case: :lower)
  end

  def risk_snapshot(ip_hash, now \\ DateTime.utc_now()) when is_binary(ip_hash) do
    since = DateTime.add(now, -@risk_window_seconds, :second)

    from(a in Attempt,
      where: a.ip_hash == ^ip_hash and a.inserted_at > ^since and a.inserted_at <= ^now,
      select: %{
        task_count: coalesce(sum(a.task_count), 0),
        distinct_guest_count: count(a.guest_user_id, :distinct)
      }
    )
    |> Repo.one!()
  end

  def guest_has_attempts?(guest_user_id) when is_binary(guest_user_id) do
    Repo.exists?(from(a in Attempt, where: a.guest_user_id == ^guest_user_id))
  end

  def guest_has_attempts?(_guest_user_id), do: false

  def reserve_attempt(attrs, now \\ DateTime.utc_now())

  def reserve_attempt(attrs, now) when is_map(attrs) do
    changeset = Attempt.changeset(%Attempt{}, attrs)

    if changeset.valid? do
      do_reserve_attempt(attrs, now)
    else
      {:error, :invalid_attempt}
    end
  end

  def reserve_attempt(_attrs, _now), do: {:error, :invalid_attempt}

  defp do_reserve_attempt(attrs, now) do
    Repo.transaction(fn ->
      request_id = Map.get(attrs, :request_id) || Map.get(attrs, "request_id")

      if Repo.exists?(from(a in Attempt, where: a.request_id == ^request_id)) do
        Repo.rollback(:attempt_duplicate)
      end

      ip_hash = Map.get(attrs, :ip_hash) || Map.get(attrs, "ip_hash")
      task_count = Map.get(attrs, :task_count) || Map.get(attrs, "task_count")

      lock_ip_hash(ip_hash)

      if rolling_task_count(ip_hash, now) + valid_task_count(task_count) > @daily_limit do
        Repo.rollback(:guest_ip_limited)
      end

      %Attempt{}
      |> Attempt.changeset(attrs)
      |> Ecto.Changeset.put_change(:inserted_at, now)
      |> Repo.insert()
      |> case do
        {:ok, attempt} ->
          attempt

        {:error, changeset} ->
          if duplicate_request_id?(changeset) do
            Repo.rollback(:attempt_duplicate)
          else
            Repo.rollback(changeset)
          end
      end
    end)
  end

  defp rolling_task_count(ip_hash, now) do
    since = DateTime.add(now, -@quota_window_seconds, :second)

    from(a in Attempt,
      where: a.ip_hash == ^ip_hash and a.inserted_at > ^since and a.inserted_at <= ^now,
      select: coalesce(sum(a.task_count), 0)
    )
    |> Repo.one!()
  end

  defp lock_ip_hash(ip_hash) when is_binary(ip_hash) do
    <<unsigned::unsigned-64, _rest::binary>> = Base.decode16!(ip_hash, case: :mixed)

    signed =
      if unsigned > 9_223_372_036_854_775_807,
        do: unsigned - 18_446_744_073_709_551_616,
        else: unsigned

    Repo.query!("SELECT pg_advisory_xact_lock($1)", [signed])
  end

  defp lock_ip_hash(_ip_hash), do: Repo.rollback(:invalid_attempt)

  defp valid_task_count(value) when is_integer(value) and value in 1..5, do: value
  defp valid_task_count(_value), do: Repo.rollback(:invalid_attempt)

  defp duplicate_request_id?(changeset) do
    Enum.any?(changeset.errors, fn
      {:request_id, {_message, opts}} -> opts[:constraint] == :unique
      _error -> false
    end)
  end

  defp ip_hash_secret do
    case Application.get_env(:sticker, :guest_ip_hash_secret) do
      secret when is_binary(secret) and byte_size(secret) >= 16 -> secret
      _other -> derived_secret_key_base()
    end
  end

  defp derived_secret_key_base do
    secret_key_base =
      :sticker
      |> Application.fetch_env!(StickerWeb.Endpoint)
      |> Keyword.fetch!(:secret_key_base)

    :crypto.mac(:hmac, :sha256, secret_key_base, "guest-ip-hash-v1")
  end
end
