defmodule Sticker.LoadTelemetryTest do
  use ExUnit.Case, async: true

  @stop_event [:sticker, :ui_load, :stop]
  @exception_event [:sticker, :ui_load, :exception]

  setup do
    handler_id = "load-telemetry-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [@stop_event, @exception_event],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "measure/3 emits bounded, privacy-safe success metadata" do
    result =
      Sticker.LoadTelemetry.measure(
        :account_recent,
        %{
          limit: 12,
          prompt: "private prompt",
          email: "private@example.com",
          image_url: "https://private.example/image.png",
          payment_id: "private-payment"
        },
        fn -> [%{id: 1}, %{id: 2}] end
      )

    assert result == [%{id: 1}, %{id: 2}]

    assert_receive {:telemetry_event, @stop_event, %{duration: duration}, metadata}
    assert is_integer(duration)
    assert duration >= 0
    assert metadata.section == :account_recent
    assert metadata.status == :ok
    assert metadata.item_count == 2
    assert metadata.limit == 12

    refute Map.has_key?(metadata, :prompt)
    refute Map.has_key?(metadata, :email)
    refute Map.has_key?(metadata, :image_url)
    refute Map.has_key?(metadata, :payment_id)
  end

  test "measure/3 emits an exception event and re-raises" do
    assert_raise RuntimeError, "load failed", fn ->
      Sticker.LoadTelemetry.measure(:history_page, %{page: 0}, fn ->
        raise "load failed"
      end)
    end

    assert_receive {:telemetry_event, @exception_event, %{duration: duration}, metadata}
    assert is_integer(duration)
    assert metadata.section == :history_page
    assert metadata.page == 0
    assert metadata.kind == :error
    assert metadata.reason == %RuntimeError{message: "load failed"}
  end
end
