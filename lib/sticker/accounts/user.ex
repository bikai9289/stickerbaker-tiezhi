defmodule Sticker.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :public_id, :string

    timestamps()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> update_change(:email, &normalize_email/1)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> validate_length(:password, min: 8, max: 72)
    |> unique_constraint(:email, name: :users_email_lower_index)
    |> unique_constraint(:public_id)
    |> put_public_id()
    |> put_password_hash()
  end

  defp normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_email(email), do: email

  defp put_public_id(changeset) do
    case get_field(changeset, :public_id) do
      nil -> put_change(changeset, :public_id, "usr_" <> random_token(18))
      _public_id -> changeset
    end
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true} = changeset) do
    password = get_change(changeset, :password)
    put_change(changeset, :hashed_password, hash_password(password))
  end

  defp put_password_hash(changeset), do: changeset

  def hash_password(password) when is_binary(password) do
    iterations = 210_000
    salt = :crypto.strong_rand_bytes(16)
    hash = :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, 32)

    Enum.join(
      [
        "pbkdf2_sha256",
        Integer.to_string(iterations),
        Base.url_encode64(salt, padding: false),
        Base.url_encode64(hash, padding: false)
      ],
      "$"
    )
  end

  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and is_binary(password) do
    with ["pbkdf2_sha256", iterations, salt, hash] <- String.split(hashed_password, "$"),
         {iterations, ""} <- Integer.parse(iterations),
         {:ok, salt} <- Base.url_decode64(salt, padding: false),
         {:ok, hash} <- Base.url_decode64(hash, padding: false) do
      candidate = :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, byte_size(hash))
      Plug.Crypto.secure_compare(candidate, hash)
    else
      _ -> false
    end
  end

  def valid_password?(_, _), do: false

  defp random_token(bytes) do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
