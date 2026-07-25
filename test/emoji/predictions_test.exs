defmodule Sticker.PredictionsTest do
  use Sticker.DataCase

  alias Sticker.Predictions

  describe "predictions" do
    alias Sticker.Predictions.Prediction

    import Sticker.PredictionsFixtures
    import Sticker.AccountsFixtures

    @invalid_attrs %{sticker_output: nil, prompt: nil, uuid: nil}

    test "list_predictions/0 returns all predictions" do
      prediction = prediction_fixture()
      assert Predictions.list_predictions() == [prediction]
    end

    test "get_prediction!/1 returns the prediction with given id" do
      prediction = prediction_fixture()
      assert Predictions.get_prediction!(prediction.id) == prediction
    end

    test "create_prediction/1 with valid data creates a prediction" do
      valid_attrs = %{sticker_output: "some output", prompt: "some prompt", uuid: "some uuid"}

      assert {:ok, %Prediction{} = prediction} = Predictions.create_prediction(valid_attrs)
      assert prediction.sticker_output == "some output"
      assert prediction.prompt == "some prompt"
      assert prediction.uuid == "some uuid"
    end

    test "create_prediction/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Predictions.create_prediction(@invalid_attrs)
    end

    test "update_prediction/2 with valid data updates the prediction" do
      prediction = prediction_fixture()

      update_attrs = %{
        sticker_output: "some updated output",
        prompt: "some updated prompt",
        uuid: "some updated uuid"
      }

      assert {:ok, %Prediction{} = prediction} =
               Predictions.update_prediction(prediction, update_attrs)

      assert prediction.sticker_output == "some updated output"
      assert prediction.prompt == "some updated prompt"
      assert prediction.uuid == "some updated uuid"
    end

    test "update_prediction/2 with invalid data returns error changeset" do
      prediction = prediction_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Predictions.update_prediction(prediction, @invalid_attrs)

      assert prediction == Predictions.get_prediction!(prediction.id)
    end

    test "delete_prediction/1 deletes the prediction" do
      prediction = prediction_fixture()
      assert {:ok, %Prediction{}} = Predictions.delete_prediction(prediction)
      assert_raise Ecto.NoResultsError, fn -> Predictions.get_prediction!(prediction.id) end
    end

    test "viewable_by?/3 allows public stickers and protects private stickers" do
      user = user_fixture()

      public_prediction =
        prediction_fixture(%{local_user_id: "another-user", is_featured: true})

      private_prediction =
        prediction_fixture(%{local_user_id: user.public_id, is_featured: nil})

      assert Predictions.viewable_by?(public_prediction, nil, nil)
      refute Predictions.viewable_by?(private_prediction, nil, nil)
      assert Predictions.viewable_by?(private_prediction, user, nil)
      assert Predictions.viewable_by?(private_prediction, nil, user.public_id)
    end

    test "get_prediction_by_media_key/1 finds generated prediction media by id key" do
      prediction =
        prediction_fixture(%{
          sticker_output: "https://example.com/media/prediction-123-sticker.png"
        })

      assert Predictions.get_prediction_by_media_key("prediction-#{prediction.id}-sticker.png").id ==
               prediction.id
    end

    test "change_prediction/1 returns a prediction changeset" do
      prediction = prediction_fixture()
      assert %Ecto.Changeset{} = Predictions.change_prediction(prediction)
    end

    test "list_user_predictions/2 filters by status, favorites, and query" do
      user = user_fixture()

      completed =
        prediction_fixture(%{
          local_user_id: user.public_id,
          prompt: "cute panda",
          status: :succeeded,
          is_favorite: true
        })

      _failed =
        prediction_fixture(%{
          local_user_id: user.public_id,
          prompt: "robot mascot",
          status: :failed
        })

      assert [^completed] =
               Predictions.list_user_predictions(user.public_id, %{
                 status: "favorites",
                 query: "panda"
               })
    end

    test "list_user_predictions/2 filters by batch" do
      user = user_fixture()

      first =
        prediction_fixture(%{
          local_user_id: user.public_id,
          prompt: "batch panda",
          batch_id: "batch-one"
        })

      _second =
        prediction_fixture(%{
          local_user_id: user.public_id,
          prompt: "batch robot",
          batch_id: "batch-two"
        })

      assert [^first] =
               Predictions.list_user_predictions(user.public_id, %{
                 status: "all",
                 query: "",
                 batch_id: "batch-one"
               })
    end

    test "list_user_recent_predictions/2 ignores orphaned records with no status or output" do
      user = user_fixture()

      completed =
        prediction_fixture(%{
          local_user_id: user.public_id,
          status: :succeeded,
          sticker_output: "https://example.com/sticker.webp"
        })

      processing =
        prediction_fixture(%{
          local_user_id: user.public_id,
          status: :processing,
          sticker_output: nil
        })

      failed =
        prediction_fixture(%{
          local_user_id: user.public_id,
          status: :failed,
          sticker_output: nil
        })

      _orphaned =
        prediction_fixture(%{
          local_user_id: user.public_id,
          status: nil,
          sticker_output: nil,
          no_bg_output: nil
        })

      recent_ids =
        user.public_id
        |> Predictions.list_user_recent_predictions(12)
        |> Enum.map(& &1.id)
        |> MapSet.new()

      assert recent_ids == MapSet.new([failed.id, processing.id, completed.id])
    end

    test "list_latest_safe_predictions/2 returns generated public stickers" do
      public =
        prediction_fixture(%{
          sticker_output: "https://example.com/public.webp",
          is_featured: true,
          status: :succeeded
        })

      _private =
        prediction_fixture(%{
          sticker_output: "https://example.com/private.webp",
          is_featured: nil,
          status: :succeeded
        })

      assert [^public] = Predictions.list_latest_safe_predictions(0, 20)
    end

    test "list_featured_showcase_predictions/1 returns public stickers by popularity" do
      older =
        prediction_fixture(%{
          sticker_output: "https://example.com/older.webp",
          is_featured: true,
          score: 1,
          status: :succeeded
        })

      popular =
        prediction_fixture(%{
          sticker_output: "https://example.com/popular.webp",
          is_featured: true,
          score: 9,
          status: :succeeded
        })

      _private =
        prediction_fixture(%{
          sticker_output: "https://example.com/private.webp",
          is_featured: nil,
          score: 99,
          status: :succeeded
        })

      assert [^popular, ^older] = Predictions.list_featured_showcase_predictions(4)
    end

    test "face to sticker results can be made private in bulk" do
      public_face =
        prediction_fixture(%{
          sticker_output: "https://example.com/face.png",
          model: "face-to-sticker",
          is_featured: true,
          status: :succeeded
        })

      public_text =
        prediction_fixture(%{
          sticker_output: "https://example.com/text.webp",
          model: "sticker-maker",
          is_featured: true,
          status: :succeeded
        })

      assert {1, nil} = Predictions.private_generated_face_stickers()

      assert is_nil(Predictions.get_prediction!(public_face.id).is_featured)
      assert Predictions.get_prediction!(public_text.id).is_featured == true
    end

    test "list_user_batches/1 returns batch status counts" do
      user = user_fixture()

      prediction_fixture(%{local_user_id: user.public_id, batch_id: "batch-a", status: :succeeded})

      prediction_fixture(%{local_user_id: user.public_id, batch_id: "batch-a", status: :failed})

      prediction_fixture(%{
        local_user_id: user.public_id,
        batch_id: "batch-a",
        status: :processing
      })

      assert [%{batch_id: "batch-a", total: 3, completed: 1, failed: 1, processing: 1}] =
               Predictions.list_user_batches(user.public_id)
    end

    test "paginate_user_predictions/4 returns one page and total count" do
      user = user_fixture()

      Enum.each(1..3, fn index ->
        prediction_fixture(%{local_user_id: user.public_id, prompt: "page #{index}"})
      end)

      page =
        Predictions.paginate_user_predictions(
          user.public_id,
          %{status: "all", query: "", batch_id: "all"},
          0,
          2
        )

      assert length(page.entries) == 2
      assert page.total == 3
      assert page.has_more? == true
    end

    test "fail_prediction_and_refund/1 refunds a credit only once" do
      user = user_fixture()

      prediction =
        prediction_fixture(%{
          local_user_id: user.public_id,
          status: :processing,
          credit_refunded: false
        })

      {:ok, prediction} =
        Predictions.fail_prediction_and_refund(prediction, :generation, "timeout")

      assert prediction.status == :failed
      assert prediction.credit_refunded == true
      assert prediction.failure_stage == "generation"
      assert prediction.failure_reason =~ "timeout"
      assert Sticker.Accounts.get_user(user.id).credits == user.credits + 1

      {:ok, prediction} = Predictions.fail_prediction_and_refund(prediction)
      assert prediction.credit_refunded == true
      assert Sticker.Accounts.get_user(user.id).credits == user.credits + 1
    end

    test "fail_prediction_and_refund/1 refunds guest credits to the guest ledger" do
      local_user_id = "guest_failed_one"
      {:ok, guest_trial} = Sticker.GuestTrials.spend_credits(local_user_id, 1)
      assert guest_trial.credits_remaining == 2

      prediction =
        prediction_fixture(%{
          local_user_id: local_user_id,
          credit_source: "guest",
          credit_owner_id: local_user_id,
          status: :processing,
          credit_refunded: false
        })

      {:ok, prediction} =
        Predictions.fail_prediction_and_refund(prediction, :generation, "timeout")

      assert prediction.status == :failed
      assert prediction.credit_refunded == true
      assert Sticker.GuestTrials.get_allowance(local_user_id).credits_remaining == 3

      {:ok, _prediction} = Predictions.fail_prediction_and_refund(prediction)
      assert Sticker.GuestTrials.get_allowance(local_user_id).credits_remaining == 3
    end

    test "has_credits?/2 checks account balance before upload consumption" do
      assert Sticker.Accounts.has_credits?(user_fixture(%{credits: 1}), 1)

      user = user_fixture()
      Sticker.Accounts.spend_credits(user, user.credits)

      refute Sticker.Accounts.has_credits?(Sticker.Accounts.get_user(user.id), 1)
      refute Sticker.Accounts.has_credits?(nil, 1)
    end

    test "new accounts unlock free credits only after email confirmation" do
      user = user_fixture(%{confirmed: false})

      assert user.credits == 0
      assert is_binary(user.confirmation_token)
      refute Sticker.Accounts.confirmed?(user)

      {:ok, user} = Sticker.Accounts.confirm_user(user.confirmation_token)

      assert user.credits == 3
      assert Sticker.Accounts.confirmed?(user)
      assert user.confirmation_token == nil
    end

    test "check_generation_limits/3 rejects too many active predictions" do
      user = user_fixture()

      Enum.each(1..8, fn index ->
        prediction_fixture(%{
          local_user_id: user.public_id,
          prompt: "active #{index}",
          status: :processing
        })
      end)

      assert {:error, :active_limited} = Predictions.check_generation_limits(user.public_id, 1)
    end

    test "check_generation_limits/3 rejects excessive daily predictions" do
      user = user_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Enum.each(1..80, fn index ->
        prediction_fixture(%{
          local_user_id: user.public_id,
          prompt: "daily #{index}",
          status: :succeeded,
          inserted_at: now,
          updated_at: now
        })
      end)

      assert {:error, :rate_limited} = Predictions.check_generation_limits(user.public_id, 1, now)
    end

    test "cancel_user_batch/2 cancels processing items and refunds each credit" do
      user = user_fixture()

      prediction_fixture(%{
        local_user_id: user.public_id,
        batch_id: "batch-cancel",
        status: :processing
      })

      prediction_fixture(%{
        local_user_id: user.public_id,
        batch_id: "batch-cancel",
        status: :starting
      })

      prediction_fixture(%{
        local_user_id: user.public_id,
        batch_id: "batch-cancel",
        status: :succeeded
      })

      {:ok, predictions} = Predictions.cancel_user_batch("batch-cancel", user.public_id)

      assert length(predictions) == 2
      assert Sticker.Accounts.get_user(user.id).credits == user.credits + 2
    end

    test "restart_user_predictions/2 restarts retryable batch items" do
      user = user_fixture()

      retryable =
        prediction_fixture(%{
          local_user_id: user.public_id,
          batch_id: "batch-retry",
          status: :failed,
          sticker_output: "https://example.com/sticker.webp",
          credit_refunded: true,
          failure_stage: "generation",
          failure_reason: "timeout"
        })

      _face =
        prediction_fixture(%{
          local_user_id: user.public_id,
          batch_id: "batch-retry",
          status: :failed,
          model: "face-to-sticker"
        })

      [prediction] = Predictions.restart_user_predictions([retryable.id], user.public_id)

      assert prediction.status == :starting
      assert prediction.failure_stage == nil
      assert prediction.failure_reason == nil
    end

    test "cancel_user_prediction/2 cancels processing prediction and refunds credit" do
      user = user_fixture()

      prediction =
        prediction_fixture(%{
          local_user_id: user.public_id,
          status: :processing,
          credit_refunded: false
        })

      {:ok, prediction} = Predictions.cancel_user_prediction(prediction.id, user.public_id)

      assert prediction.status == :canceled
      assert Sticker.Accounts.get_user(user.id).credits == user.credits + 1
    end

    test "cancel_user_prediction/2 refunds guest-funded predictions to the guest ledger" do
      local_user_id = "guest_cancel_one"
      {:ok, guest_trial} = Sticker.GuestTrials.spend_credits(local_user_id, 1)
      assert guest_trial.credits_remaining == 2

      prediction =
        prediction_fixture(%{
          local_user_id: local_user_id,
          credit_source: "guest",
          credit_owner_id: local_user_id,
          status: :processing,
          credit_refunded: false
        })

      {:ok, prediction} = Predictions.cancel_user_prediction(prediction.id, local_user_id)

      assert prediction.status == :canceled
      assert prediction.credit_refunded == true
      assert Sticker.GuestTrials.get_allowance(local_user_id).credits_remaining == 3
    end

    test "transfer_user_predictions/2 preserves original guest credit owner" do
      user = user_fixture()
      local_user_id = "guest_transfer_one"

      prediction =
        prediction_fixture(%{
          local_user_id: local_user_id,
          credit_source: "guest",
          credit_owner_id: local_user_id
        })

      assert {1, nil} = Predictions.transfer_user_predictions(local_user_id, user.public_id)

      prediction = Predictions.get_prediction!(prediction.id)
      assert prediction.local_user_id == user.public_id
      assert prediction.credit_source == "guest"
      assert prediction.credit_owner_id == local_user_id
    end

    test "restart_user_prediction/2 resets failed text prediction" do
      user = user_fixture()

      prediction =
        prediction_fixture(%{
          local_user_id: user.public_id,
          status: :failed,
          sticker_output: "https://example.com/sticker.webp",
          output_format: "webp",
          credit_refunded: true
        })

      {:ok, prediction} = Predictions.restart_user_prediction(prediction.id, user.public_id)

      assert prediction.status == :starting
      assert prediction.sticker_output == nil
      assert prediction.output_format == nil
      assert prediction.credit_refunded == false
      assert prediction.failure_stage == nil
      assert prediction.failure_reason == nil
    end

    test "restart_user_prediction/2 rejects older upload based stickers without stored source" do
      user = user_fixture()

      prediction =
        prediction_fixture(%{
          local_user_id: user.public_id,
          status: :failed,
          model: "face-to-sticker"
        })

      assert {:error, :not_retryable} =
               Predictions.restart_user_prediction(prediction.id, user.public_id)
    end

    test "restart_user_prediction/2 accepts upload based stickers with stored source" do
      user = user_fixture()

      prediction =
        prediction_fixture(%{
          local_user_id: user.public_id,
          status: :failed,
          model: "face-to-sticker",
          source_image_url: "https://example.com/source.png",
          source_image_content_type: "image/png"
        })

      assert {:ok, prediction} =
               Predictions.restart_user_prediction(prediction.id, user.public_id)

      assert prediction.status == :starting
      assert prediction.source_image_url == "https://example.com/source.png"
    end
  end
end
