defmodule Sticker.GuestGenerationGate do
  alias Sticker.GuestAbuse
  alias Sticker.GuestTrials
  alias Sticker.Turnstile

  @guest_id_format ~r/^[A-Za-z0-9_-]{6,128}$/

  def challenge_requirement(attrs, now \\ DateTime.utc_now())

  def challenge_requirement(%{current_user: current_user}, _now) when not is_nil(current_user) do
    {:ok, %{challenge_required?: false, challenge_reason: nil}}
  end

  def challenge_requirement(attrs, now) when is_map(attrs) do
    with {:ok, guest_user_id} <- validate_guest_user_id(attrs[:guest_user_id]),
         {:ok, canonical_ip} <- validate_ip(attrs[:canonical_ip]),
         {:ok, _mode} <- validate_mode(attrs[:mode]),
         {:ok, task_count} <- validate_task_count(attrs[:task_count]),
         :ok <- validate_guest_credits(guest_user_id, task_count) do
      reason = challenge_reason(guest_user_id, GuestAbuse.ip_hash(canonical_ip), now)
      required? = Turnstile.configured?() and not is_nil(reason)

      {:ok,
       %{
         challenge_required?: required?,
         challenge_reason: if(required?, do: reason)
       }}
    end
  end

  def challenge_requirement(_attrs, _now), do: {:error, :invalid_generation_request}

  def authorize(attrs, now \\ DateTime.utc_now())

  def authorize(%{current_user: current_user}, _now) when not is_nil(current_user) do
    {:ok,
     %{
       authenticated?: true,
       challenge_required?: false,
       challenge_reason: nil,
       attempt: nil
     }}
  end

  def authorize(attrs, now) when is_map(attrs) do
    with {:ok, guest_user_id} <- validate_guest_user_id(attrs[:guest_user_id]),
         {:ok, canonical_ip} <- validate_ip(attrs[:canonical_ip]),
         {:ok, request_id} <- validate_request_id(attrs[:request_id]),
         {:ok, mode} <- validate_mode(attrs[:mode]),
         {:ok, task_count} <- validate_task_count(attrs[:task_count]),
         :ok <- validate_guest_credits(guest_user_id, task_count),
         ip_hash = GuestAbuse.ip_hash(canonical_ip),
         challenge_reason <- challenge_reason(guest_user_id, ip_hash, now),
         challenge_required? = Turnstile.configured?() and not is_nil(challenge_reason),
         :ok <-
           verify_challenge(
             challenge_required?,
             attrs[:turnstile_token],
             canonical_ip,
             request_id
           ),
         {:ok, attempt} <-
           GuestAbuse.reserve_attempt(
             %{
               request_id: request_id,
               guest_user_id: guest_user_id,
               ip_hash: ip_hash,
               mode: Atom.to_string(mode),
               task_count: task_count,
               turnstile_required: challenge_required?,
               turnstile_verified: challenge_required?,
               risk_reason: encode_reason(challenge_required?, challenge_reason)
             },
             now
           ) do
      {:ok,
       %{
         authenticated?: false,
         challenge_required?: challenge_required?,
         challenge_reason: if(challenge_required?, do: challenge_reason),
         attempt: attempt
       }}
    end
  end

  def authorize(_attrs, _now), do: {:error, :invalid_generation_request}

  defp validate_guest_user_id(value) when is_binary(value) do
    value = String.trim(value)

    if Regex.match?(@guest_id_format, value) do
      {:ok, value}
    else
      {:error, :guest_identity_missing}
    end
  end

  defp validate_guest_user_id(_value), do: {:error, :guest_identity_missing}

  defp validate_ip(value) when is_binary(value) do
    value = String.trim(value)

    case :inet.parse_address(String.to_charlist(value)) do
      {:ok, address} -> {:ok, address |> :inet.ntoa() |> to_string()}
      {:error, _reason} -> {:error, :invalid_generation_request}
    end
  end

  defp validate_ip(_value), do: {:error, :invalid_generation_request}

  defp validate_request_id(value) do
    case Ecto.UUID.cast(value) do
      {:ok, request_id} -> {:ok, request_id}
      :error -> {:error, :invalid_generation_request}
    end
  end

  defp validate_mode(mode) when mode in [:text, :portrait], do: {:ok, mode}
  defp validate_mode(_mode), do: {:error, :invalid_generation_request}

  defp validate_task_count(task_count) when is_integer(task_count) and task_count in 1..5,
    do: {:ok, task_count}

  defp validate_task_count(_task_count), do: {:error, :invalid_generation_request}

  defp validate_guest_credits(guest_user_id, task_count) do
    if GuestTrials.has_credits?(guest_user_id, task_count) do
      :ok
    else
      {:error, :guest_credits_exhausted}
    end
  end

  defp challenge_reason(guest_user_id, ip_hash, now) do
    allowance = GuestTrials.get_allowance(guest_user_id)
    risk = GuestAbuse.risk_snapshot(ip_hash, now)

    cond do
      (allowance && allowance.credits_spent > 0) or
          GuestAbuse.guest_has_attempts?(guest_user_id) ->
        :repeat_guest

      risk.task_count >= 3 ->
        :ip_velocity

      risk.distinct_guest_count >= 2 ->
        :identity_velocity

      true ->
        nil
    end
  end

  defp verify_challenge(false, _token, _canonical_ip, _request_id), do: :ok

  defp verify_challenge(true, token, _canonical_ip, _request_id)
       when not is_binary(token) or token == "",
       do: {:error, :turnstile_required}

  defp verify_challenge(true, token, canonical_ip, request_id) do
    case String.trim(token) do
      "" -> {:error, :turnstile_required}
      token -> verifier().verify(token, canonical_ip, request_id)
    end
  end

  defp verifier do
    Application.get_env(:sticker, :turnstile_verifier, Turnstile)
  end

  defp encode_reason(true, reason), do: Atom.to_string(reason)
  defp encode_reason(false, _reason), do: nil
end
