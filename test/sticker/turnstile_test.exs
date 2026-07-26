defmodule Sticker.TurnstileTest do
  use ExUnit.Case, async: false

  alias Sticker.Turnstile

  defmodule HTTPStub do
    def post(url, form) do
      send(Process.get(:turnstile_test_pid), {:siteverify_request, url, form})
      Process.get(:turnstile_response)
    end
  end

  setup do
    previous_config = Application.get_env(:sticker, :turnstile)
    previous_client = Application.get_env(:sticker, :turnstile_http_client)

    Process.put(:turnstile_test_pid, self())
    Application.put_env(:sticker, :turnstile_http_client, HTTPStub)

    on_exit(fn ->
      restore_env(:turnstile, previous_config)
      restore_env(:turnstile_http_client, previous_client)
    end)

    :ok
  end

  test "configuration is disabled with no keys, enabled with both, and rejects partial keys" do
    assert {:ok, [enabled: false]} = Turnstile.validate_config(nil, nil)

    assert {:ok, config} = Turnstile.validate_config("site-key", "secret-key")
    assert config[:enabled]
    assert config[:site_key] == "site-key"
    assert config[:secret_key] == "secret-key"

    assert {:error, :partial_config} = Turnstile.validate_config("site-key", nil)
    assert {:error, :partial_config} = Turnstile.validate_config(nil, "secret-key")
    assert {:error, :partial_config} = Turnstile.validate_config("", "secret-key")
  end

  test "successful verification sends the complete Siteverify form" do
    enable_turnstile()

    Process.put(
      :turnstile_response,
      {:ok,
       %{
         status: 200,
         body:
           Jason.encode!(%{
             success: true,
             hostname: "ai-sticker-maker.com",
             action: "sticker_generation"
           })
       }}
    )

    request_id = Ecto.UUID.generate()
    assert :ok = Turnstile.verify("fresh-token", "203.0.113.20", request_id)

    assert_receive {:siteverify_request,
                    "https://challenges.cloudflare.com/turnstile/v0/siteverify", form}

    assert form == %{
             "secret" => "secret-key",
             "response" => "fresh-token",
             "remoteip" => "203.0.113.20",
             "idempotency_key" => request_id
           }
  end

  test "successful verification uses safe hostname and action defaults" do
    Application.put_env(:sticker, :turnstile,
      enabled: true,
      site_key: "site-key",
      secret_key: "secret-key"
    )

    Process.put(
      :turnstile_response,
      {:ok,
       %{
         status: 200,
         body:
           Jason.encode!(%{
             success: true,
             hostname: "ai-sticker-maker.com",
             action: "sticker_generation"
           })
       }}
    )

    assert :ok = Turnstile.verify("fresh-token", "203.0.113.20", Ecto.UUID.generate())
  end

  test "missing, expired, invalid, wrong-host, and wrong-action responses map distinctly" do
    enable_turnstile()

    assert {:error, :turnstile_required} =
             Turnstile.verify("", "203.0.113.21", Ecto.UUID.generate())

    assert_verify_error(
      %{"success" => false, "error-codes" => ["timeout-or-duplicate"]},
      :turnstile_expired
    )

    assert_verify_error(
      %{"success" => false, "error-codes" => ["invalid-input-response"]},
      :turnstile_invalid
    )

    assert_verify_error(
      %{"success" => true, "hostname" => "evil.example", "action" => "sticker_generation"},
      :turnstile_invalid
    )

    assert_verify_error(
      %{"success" => true, "hostname" => "ai-sticker-maker.com", "action" => "other"},
      :turnstile_invalid
    )
  end

  test "network, 5xx, and malformed responses map to unavailable or invalid" do
    enable_turnstile()

    Process.put(:turnstile_response, {:error, :timeout})

    assert {:error, :turnstile_unavailable} =
             Turnstile.verify("token", "203.0.113.22", Ecto.UUID.generate())

    Process.put(:turnstile_response, {:ok, %{status: 503, body: "unavailable"}})

    assert {:error, :turnstile_unavailable} =
             Turnstile.verify("token", "203.0.113.22", Ecto.UUID.generate())

    Process.put(:turnstile_response, {:ok, %{status: 200, body: "not-json"}})

    assert {:error, :turnstile_invalid} =
             Turnstile.verify("token", "203.0.113.22", Ecto.UUID.generate())

    Process.put(
      :turnstile_response,
      {:ok,
       %{
         status: 200,
         body: Jason.encode!(%{"success" => false, "error-codes" => "invalid-response"})
       }}
    )

    assert {:error, :turnstile_invalid} =
             Turnstile.verify("token", "203.0.113.22", Ecto.UUID.generate())
  end

  defp assert_verify_error(response, expected) do
    Process.put(:turnstile_response, {:ok, %{status: 200, body: Jason.encode!(response)}})
    assert {:error, ^expected} = Turnstile.verify("token", "203.0.113.23", Ecto.UUID.generate())
  end

  defp enable_turnstile do
    Application.put_env(:sticker, :turnstile,
      enabled: true,
      site_key: "site-key",
      secret_key: "secret-key",
      expected_hostnames: ["ai-sticker-maker.com"],
      action: "sticker_generation"
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:sticker, key)
  defp restore_env(key, value), do: Application.put_env(:sticker, key, value)
end
