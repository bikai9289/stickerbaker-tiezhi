defmodule StickerWeb.ReplicateWebhookControllerTest do
  use StickerWeb.ConnCase

  import Sticker.PredictionsFixtures

  alias Sticker.Predictions.Prediction
  alias Sticker.Repo

  defmodule ProviderStub do
    def gen_image(prompt, user_id, prediction_id) do
      send(Application.fetch_env!(:sticker, :webhook_generation_test_pid), {
        :image_generation_started,
        prompt,
        user_id,
        prediction_id,
        self()
      })

      {:ok,
       %Replicate.Predictions.Prediction{
         id: "webhook-remote-image-1",
         status: "starting"
       }}
    end
  end

  setup do
    previous_provider = Application.get_env(:sticker, :generation_provider)
    previous_pid = Application.get_env(:sticker, :webhook_generation_test_pid)

    Application.put_env(:sticker, :generation_provider, ProviderStub)
    Application.put_env(:sticker, :webhook_generation_test_pid, self())

    on_exit(fn ->
      restore_application_env(:generation_provider, previous_provider)
      restore_application_env(:webhook_generation_test_pid, previous_pid)
    end)

    :ok
  end

  test "successful moderation durably starts image generation", %{conn: conn} do
    prediction =
      prediction_fixture(%{
        prompt: "a webhook cat",
        local_user_id: "webhook-user",
        status: :starting,
        sticker_output: nil,
        uuid: nil
      })

    prediction_id = prediction.id

    conn =
      post(
        conn,
        "/webhooks/replicate?user_id=webhook-user&prediction_id=#{prediction_id}",
        %{
          "status" => "succeeded",
          "output" => ["1"],
          "model" => "fofr/prompt-classifier"
        }
      )

    assert response(conn, 200) == "ok"

    assert_receive {:image_generation_started, "a webhook cat", "webhook-user", ^prediction_id,
                    task_pid}

    task_ref = Process.monitor(task_pid)
    assert_receive {:DOWN, ^task_ref, :process, ^task_pid, _reason}, 2_000

    refreshed = Repo.get!(Prediction, prediction_id)
    assert refreshed.status == :processing
    assert refreshed.uuid == "webhook-remote-image-1"
  end

  defp restore_application_env(key, nil), do: Application.delete_env(:sticker, key)
  defp restore_application_env(key, value), do: Application.put_env(:sticker, key, value)
end
