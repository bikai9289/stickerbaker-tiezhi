defmodule Sticker.GuestTrials do
  import Ecto.Query, warn: false

  alias Sticker.GuestTrials.GuestTrialCredit
  alias Sticker.Repo

  @max_trial_credits 3

  def max_trial_credits, do: @max_trial_credits

  def get_allowance(local_user_id) when is_binary(local_user_id) do
    Repo.get_by(GuestTrialCredit, local_user_id: local_user_id)
  end

  def get_allowance(_local_user_id), do: nil

  def get_or_create_allowance(local_user_id) when is_binary(local_user_id) do
    local_user_id = String.trim(local_user_id)
    now = now()

    case get_allowance(local_user_id) do
      %GuestTrialCredit{} = allowance ->
        touch_allowance(allowance, now)

      nil ->
        %GuestTrialCredit{}
        |> GuestTrialCredit.changeset(%{
          local_user_id: local_user_id,
          credits_remaining: @max_trial_credits,
          credits_spent: 0,
          credits_refunded: 0,
          last_seen_at: now
        })
        |> Repo.insert()
        |> case do
          {:ok, allowance} -> {:ok, allowance}
          {:error, _changeset} -> fetch_after_insert_race(local_user_id)
        end
    end
  end

  def get_or_create_allowance(_local_user_id), do: {:error, :invalid_guest_identity}

  def has_credits?(local_user_id, amount) when is_integer(amount) and amount > 0 do
    with {:ok, allowance} <- get_or_create_allowance(local_user_id) do
      allowance.credits_remaining >= amount
    end
  end

  def has_credits?(_local_user_id, _amount), do: false

  def spend_credits(local_user_id, amount) when is_integer(amount) and amount > 0 do
    with {:ok, _allowance} <- get_or_create_allowance(local_user_id) do
      {count, _} =
        from(g in GuestTrialCredit,
          where: g.local_user_id == ^local_user_id and g.credits_remaining >= ^amount
        )
        |> Repo.update_all(
          inc: [credits_remaining: -amount, credits_spent: amount],
          set: [last_seen_at: now()]
        )

      if count == 1 do
        {:ok, get_allowance(local_user_id)}
      else
        {:error, :guest_insufficient_credits}
      end
    end
  end

  def spend_credits(_local_user_id, _amount), do: {:error, :invalid_guest_credit_amount}

  def refund_credits(local_user_id, amount \\ 1)

  def refund_credits(local_user_id, amount)
      when is_binary(local_user_id) and is_integer(amount) and amount > 0 do
    now = now()
    max_trial_credits = @max_trial_credits

    {count, _} =
      from(g in GuestTrialCredit,
        where:
          g.local_user_id == ^local_user_id and
            g.credits_spent >= g.credits_refunded + ^amount,
        update: [
          inc: [credits_refunded: ^amount],
          set: [
            credits_remaining:
              fragment("LEAST(?, ? + ?)", ^max_trial_credits, g.credits_remaining, ^amount),
            last_seen_at: ^now
          ]
        ]
      )
      |> Repo.update_all([])

    if count == 1 do
      {:ok, get_allowance(local_user_id)}
    else
      {:error, :not_refundable}
    end
  end

  def refund_credits(_local_user_id, _amount), do: {:error, :invalid_guest_credit_amount}

  def free_credits_for_signup(local_user_id) when is_binary(local_user_id) do
    case get_allowance(local_user_id) do
      %GuestTrialCredit{credits_remaining: remaining} -> remaining
      nil -> @max_trial_credits
    end
  end

  def free_credits_for_signup(_local_user_id), do: @max_trial_credits

  defp touch_allowance(%GuestTrialCredit{} = allowance, now) do
    allowance
    |> GuestTrialCredit.changeset(%{last_seen_at: now})
    |> Repo.update()
  end

  defp fetch_after_insert_race(local_user_id) do
    case get_allowance(local_user_id) do
      %GuestTrialCredit{} = allowance -> {:ok, allowance}
      nil -> {:error, :invalid_guest_identity}
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
