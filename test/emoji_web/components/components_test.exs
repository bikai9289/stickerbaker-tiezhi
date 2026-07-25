defmodule StickerWeb.ComponentsTest do
  use StickerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Sticker.Predictions.Prediction
  alias StickerWeb.Components

  test "failed text generations do not tell users to upload a clearer portrait" do
    prediction = %Prediction{
      id: 42,
      prompt: "a tiny spaceship sticker",
      status: :failed,
      model: "text-to-image",
      credit_refunded: true,
      score: 0
    }

    html = render_component(&Components.sticker/1, id: "prediction-42", prediction: prediction)

    assert html =~ "Try again with a shorter, clearer prompt."
    refute html =~ "clearer portrait"
    assert html =~ "Credit returned"
  end
end
