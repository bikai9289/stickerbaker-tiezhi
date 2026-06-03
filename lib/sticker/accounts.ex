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
end
