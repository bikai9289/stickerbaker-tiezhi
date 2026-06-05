defmodule Sticker.Accounts do
  import Ecto.Query, warn: false

  alias Sticker.Accounts.User
  alias Sticker.Repo

  def get_user(nil), do: nil
  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    normalized_email =
      email
      |> String.trim()
      |> String.downcase()

    Repo.one(from u in User, where: u.email == ^normalized_email)
  end

  def get_user_by_public_id(public_id) when is_binary(public_id) do
    Repo.get_by(User, public_id: public_id)
  end

  def get_user_by_public_id(_public_id), do: nil

  def list_users do
    Repo.all(from u in User, order_by: [desc: u.inserted_at])
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    if User.valid_password?(user, password) do
      {:ok, user}
    else
      {:error, :invalid_credentials}
    end
  end

  def authenticate_user(_email, _password), do: {:error, :invalid_credentials}

  def change_user_registration(attrs \\ %{}) do
    User.registration_changeset(%User{}, attrs)
  end

  def spend_credit(%User{id: user_id}) do
    {count, _} =
      from(u in User, where: u.id == ^user_id and u.credits > 0)
      |> Repo.update_all(inc: [credits: -1])

    if count == 1 do
      {:ok, get_user(user_id)}
    else
      {:error, :insufficient_credits}
    end
  end

  def spend_credit(_user), do: {:error, :not_signed_in}

  def spend_credits(%User{id: user_id}, amount) when is_integer(amount) and amount > 0 do
    {count, _} =
      from(u in User, where: u.id == ^user_id and u.credits >= ^amount)
      |> Repo.update_all(inc: [credits: -amount])

    if count == 1 do
      {:ok, get_user(user_id)}
    else
      {:error, :insufficient_credits}
    end
  end

  def spend_credits(_user, _amount), do: {:error, :not_signed_in}

  def refund_credits(%User{id: user_id}, amount) when is_integer(amount) and amount > 0 do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(inc: [credits: amount])

    get_user(user_id)
  end

  def refund_credits(user, _amount), do: refund_credit(user)

  def refund_credit(%User{id: user_id}) do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(inc: [credits: 1])

    get_user(user_id)
  end

  def refund_credit(_user), do: nil

  def add_credits(user_id, amount) when is_integer(amount) and amount > 0 do
    {count, _} =
      from(u in User, where: u.id == ^user_id)
      |> Repo.update_all(inc: [credits: amount])

    if count == 1 do
      {:ok, get_user(user_id)}
    else
      {:error, :not_found}
    end
  end

  def add_credits(_user_id, _amount), do: {:error, :invalid_amount}
end
