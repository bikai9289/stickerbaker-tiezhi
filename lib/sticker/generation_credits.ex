defmodule Sticker.GenerationCredits do
  alias Sticker.Accounts
  alias Sticker.Accounts.User
  alias Sticker.GuestTrials
  alias Sticker.Predictions.Prediction

  def has_credits?(%User{} = user, _local_user_id, amount), do: Accounts.has_credits?(user, amount)
  def has_credits?(nil, local_user_id, amount), do: GuestTrials.has_credits?(local_user_id, amount)
  def has_credits?(_user, _local_user_id, _amount), do: false

  def spend(%User{} = user, _local_user_id, amount) do
    with {:ok, user} <- Accounts.spend_credits(user, amount) do
      {:ok,
       %{
         current_user: user,
         guest_trial: nil,
         credit_source: "account",
         credit_owner_id: user.public_id
       }}
    end
  end

  def spend(nil, local_user_id, amount) when is_binary(local_user_id) do
    with {:ok, guest_trial} <- GuestTrials.spend_credits(local_user_id, amount) do
      {:ok,
       %{
         current_user: nil,
         guest_trial: guest_trial,
         credit_source: "guest",
         credit_owner_id: local_user_id
       }}
    end
  end

  def spend(nil, _local_user_id, _amount), do: {:error, :missing_guest_identity}
  def spend(_user, _local_user_id, _amount), do: {:error, :not_signed_in}

  def refund_prediction_credit(%Prediction{} = prediction, amount \\ 1) do
    owner_id = prediction.credit_owner_id || prediction.local_user_id

    case prediction.credit_source do
      "guest" -> GuestTrials.refund_credits(owner_id, amount)
      _source -> Accounts.refund_credit_by_public_id(owner_id)
    end
  end

  def refund("guest", owner_id, amount), do: GuestTrials.refund_credits(owner_id, amount)
  def refund("account", owner_id, amount) when is_integer(amount) and amount > 0 do
    case Accounts.get_user_by_public_id(owner_id) do
      %User{} = user -> {:ok, Accounts.refund_credits(user, amount)}
      nil -> {:error, :not_found}
    end
  end
  def refund(_source, _owner_id, _amount), do: {:error, :unknown_credit_source}
end
