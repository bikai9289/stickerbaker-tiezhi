defmodule Sticker.GenerationLauncherTest do
  use Sticker.DataCase

  import Sticker.PredictionsFixtures

  alias Sticker.GenerationLauncher
  alias Sticker.Predictions.Prediction
  alias Sticker.Repo

  defmodule ProviderStub do
    def moderate(prompt, user_id, prediction_id) do
      send(Application.fetch_env!(:sticker, :generation_test_pid), {
        :moderation_started,
        prompt,
        user_id,
        prediction_id
      })

      {:ok, :started}
    end

    def gen_face_to_sticker(prompt, image_uri, user_id, prediction_id) do
      send(Application.fetch_env!(:sticker, :generation_test_pid), {
        :face_generation_started,
        prompt,
        image_uri,
        user_id,
        prediction_id
      })

      {:ok, :started}
    end

    def gen_image(prompt, user_id, prediction_id) do
      send(Application.fetch_env!(:sticker, :generation_test_pid), {
        :image_generation_started,
        prompt,
        user_id,
        prediction_id,
        self()
      })

      Application.fetch_env!(:sticker, :generation_image_response)
    end
  end

  setup do
    previous_provider = Application.get_env(:sticker, :generation_provider)
    previous_pid = Application.get_env(:sticker, :generation_test_pid)
    previous_image_response = Application.get_env(:sticker, :generation_image_response)

    Application.put_env(:sticker, :generation_provider, ProviderStub)
    Application.put_env(:sticker, :generation_test_pid, self())

    Application.put_env(
      :sticker,
      :generation_image_response,
      {:ok, %Replicate.Predictions.Prediction{id: "remote-image-1", status: "starting"}}
    )

    on_exit(fn ->
      restore_application_env(:generation_provider, previous_provider)
      restore_application_env(:generation_test_pid, previous_pid)
      restore_application_env(:generation_image_response, previous_image_response)
    end)

    :ok
  end

  test "text generation start survives the caller process exiting" do
    prediction = %Prediction{id: 42, prompt: "a cat", local_user_id: "user-42"}
    parent = self()

    caller =
      spawn(fn ->
        send(parent, {:launcher_result, GenerationLauncher.start_text(prediction)})
      end)

    caller_ref = Process.monitor(caller)

    assert_receive {:launcher_result, {:ok, task_pid}}
    assert is_pid(task_pid)
    assert_receive {:DOWN, ^caller_ref, :process, ^caller, :normal}
    assert_receive {:moderation_started, "a cat", "user-42", 42}
  end

  test "stale queued text generation is claimed and restarted" do
    stale_time = DateTime.utc_now() |> DateTime.add(-10, :minute) |> DateTime.truncate(:second)

    prediction =
      prediction_fixture(%{
        prompt: "a cat",
        local_user_id: "stale-user",
        status: :starting
      })
      |> Ecto.Changeset.change(updated_at: DateTime.to_naive(stale_time))
      |> Repo.update!()

    prediction_id = prediction.id

    assert {:ok, task_pid} = GenerationLauncher.resume_stale(prediction)
    assert is_pid(task_pid)
    assert_receive {:moderation_started, "a cat", "stale-user", ^prediction_id}
  end

  test "recent queued generation is not restarted" do
    prediction =
      prediction_fixture(%{
        prompt: "a dog",
        local_user_id: "recent-user",
        status: :starting
      })

    prediction_id = prediction.id

    assert :ignored = GenerationLauncher.resume_stale(prediction)
    refute_receive {:moderation_started, "a dog", "recent-user", ^prediction_id}
  end

  test "image generation start survives the webhook process and records the remote job" do
    prediction =
      prediction_fixture(%{
        prompt: "a cat",
        local_user_id: "image-user",
        status: :moderation_succeeded,
        sticker_output: nil,
        uuid: nil
      })

    prediction_id = prediction.id

    assert {:ok, task_pid} = GenerationLauncher.start_image(prediction)
    assert is_pid(task_pid)
    task_ref = Process.monitor(task_pid)

    assert_receive {:image_generation_started, "a cat", "image-user", ^prediction_id, ^task_pid}

    assert_receive {:DOWN, ^task_ref, :process, ^task_pid, _reason}, 2_000

    refreshed = Repo.get!(Prediction, prediction_id)
    assert refreshed.status == :processing
    assert refreshed.uuid == "remote-image-1"
  end

  test "stale moderation result with no remote job is claimed and restarted" do
    stale_time = DateTime.utc_now() |> DateTime.add(-10, :minute) |> DateTime.truncate(:second)

    prediction =
      prediction_fixture(%{
        prompt: "a recovered cat",
        local_user_id: "stale-image-user",
        status: :moderation_succeeded,
        sticker_output: nil,
        uuid: nil
      })
      |> Ecto.Changeset.change(updated_at: DateTime.to_naive(stale_time))
      |> Repo.update!()

    prediction_id = prediction.id

    assert {:ok, task_pid} = GenerationLauncher.resume_stale(prediction)
    assert is_pid(task_pid)
    task_ref = Process.monitor(task_pid)

    assert_receive {:image_generation_started, "a recovered cat", "stale-image-user",
                    ^prediction_id, ^task_pid}

    assert_receive {:DOWN, ^task_ref, :process, ^task_pid, _reason}, 2_000

    refreshed = Repo.get!(Prediction, prediction_id)
    assert refreshed.status == :processing
    assert refreshed.uuid == "remote-image-1"
  end

  test "image provider start failure fails the prediction and returns its credit" do
    Application.put_env(:sticker, :generation_image_response, {:error, :provider_unavailable})

    prediction =
      prediction_fixture(%{
        prompt: "a failed cat",
        local_user_id: "failed-image-user",
        status: :moderation_succeeded,
        sticker_output: nil,
        uuid: nil
      })

    prediction_id = prediction.id

    assert {:ok, task_pid} = GenerationLauncher.start_image(prediction)
    assert is_pid(task_pid)
    task_ref = Process.monitor(task_pid)

    assert_receive {:image_generation_started, "a failed cat", "failed-image-user",
                    ^prediction_id, ^task_pid}

    assert_receive {:DOWN, ^task_ref, :process, ^task_pid, _reason}, 2_000

    refreshed = Repo.get!(Prediction, prediction_id)
    assert refreshed.status == :failed
    assert refreshed.credit_refunded
    assert refreshed.failure_stage == "generation_start"
  end

  test "stale moderation result with a remote job is not duplicated" do
    stale_time = DateTime.utc_now() |> DateTime.add(-10, :minute) |> DateTime.truncate(:second)

    prediction =
      prediction_fixture(%{
        prompt: "an existing cat",
        local_user_id: "existing-image-user",
        status: :moderation_succeeded,
        sticker_output: nil,
        uuid: "remote-existing"
      })
      |> Ecto.Changeset.change(updated_at: DateTime.to_naive(stale_time))
      |> Repo.update!()

    prediction_id = prediction.id

    assert :ignored = GenerationLauncher.resume_stale(prediction)

    refute_receive {:image_generation_started, "an existing cat", "existing-image-user",
                    ^prediction_id, _task_pid}
  end

  defp restore_application_env(key, nil), do: Application.delete_env(:sticker, key)
  defp restore_application_env(key, value), do: Application.put_env(:sticker, key, value)
end
