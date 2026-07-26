defmodule Sticker.Turnstile.Verifier do
  @callback verify(token :: String.t(), remote_ip :: String.t(), request_id :: Ecto.UUID.t()) ::
              :ok
              | {:error,
                 :turnstile_required
                 | :turnstile_invalid
                 | :turnstile_expired
                 | :turnstile_unavailable}
end

defmodule Sticker.Turnstile.HTTPClient do
  @callback post(url :: String.t(), form :: map()) ::
              {:ok, %{status: non_neg_integer(), body: binary()}} | {:error, term()}
end

defmodule Sticker.Turnstile.FinchClient do
  @behaviour Sticker.Turnstile.HTTPClient

  @impl true
  def post(url, form) do
    request =
      Finch.build(
        :post,
        url,
        [{"content-type", "application/x-www-form-urlencoded"}],
        URI.encode_query(form)
      )

    case Finch.request(request, Sticker.Finch) do
      {:ok, %Finch.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
