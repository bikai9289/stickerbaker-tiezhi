defmodule Sticker.Turnstile do
  @behaviour Sticker.Turnstile.Verifier

  @siteverify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  def validate_config(site_key, secret_key) do
    case {normalize_key(site_key), normalize_key(secret_key)} do
      {nil, nil} -> {:ok, [enabled: false]}
      {site_key, secret_key} when is_binary(site_key) and is_binary(secret_key) ->
        {:ok, [enabled: true, site_key: site_key, secret_key: secret_key]}

      _partial ->
        {:error, :partial_config}
    end
  end

  def configured? do
    turnstile_config()[:enabled] == true
  end

  def site_key do
    if configured?(), do: turnstile_config()[:site_key]
  end

  @impl true
  def verify(token, remote_ip, request_id)
      when is_binary(token) and is_binary(remote_ip) and is_binary(request_id) do
    token = String.trim(token)

    cond do
      token == "" ->
        {:error, :turnstile_required}

      not configured?() ->
        :ok

      true ->
        request_verification(token, remote_ip, request_id)
    end
  end

  def verify(_token, _remote_ip, _request_id), do: {:error, :turnstile_invalid}

  defp request_verification(token, remote_ip, request_id) do
    form = %{
      "secret" => turnstile_config()[:secret_key],
      "response" => token,
      "remoteip" => remote_ip,
      "idempotency_key" => request_id
    }

    case http_client().post(@siteverify_url, form) do
      {:ok, %{status: 200, body: body}} -> parse_response(body)
      {:ok, %{status: status}} when status >= 500 -> {:error, :turnstile_unavailable}
      {:ok, _response} -> {:error, :turnstile_invalid}
      {:error, _reason} -> {:error, :turnstile_unavailable}
    end
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"success" => true} = response} -> validate_success(response)
      {:ok, %{"success" => false} = response} -> map_error_codes(response["error-codes"] || [])
      _invalid -> {:error, :turnstile_invalid}
    end
  end

  defp validate_success(response) do
    config = turnstile_config()
    hostname = response["hostname"]
    action = response["action"]

    hostname_valid? = is_nil(hostname) or hostname in config[:expected_hostnames]
    action_valid? = is_nil(action) or action == config[:action]

    if hostname_valid? and action_valid?, do: :ok, else: {:error, :turnstile_invalid}
  end

  defp map_error_codes(error_codes) do
    cond do
      "timeout-or-duplicate" in error_codes -> {:error, :turnstile_expired}
      "missing-input-response" in error_codes -> {:error, :turnstile_required}
      "internal-error" in error_codes -> {:error, :turnstile_unavailable}
      true -> {:error, :turnstile_invalid}
    end
  end

  defp turnstile_config do
    Application.get_env(:sticker, :turnstile, enabled: false)
  end

  defp http_client do
    Application.get_env(:sticker, :turnstile_http_client, Sticker.Turnstile.FinchClient)
  end

  defp normalize_key(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_key(_value), do: nil
end
