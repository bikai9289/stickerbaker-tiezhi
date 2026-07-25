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

  test "active generations show real stages and a sibling cancel confirmation" do
    expectations = [
      {:starting, "Checking input", "1"},
      {:moderation_succeeded, "Queued", "2"},
      {:processing, "Creating sticker", "3"}
    ]

    for {status, label, active_phase} <- expectations do
      prediction = %Prediction{
        id: System.unique_integer([:positive]),
        prompt: "active generation",
        status: status,
        model: "text-to-image",
        score: 0
      }

      html =
        render_component(&Components.sticker/1,
          id: "prediction-#{prediction.id}",
          prediction: prediction,
          cancel_event: "cancel-generation"
        )

      assert html =~ ~s(data-generation-state="#{status}")
      assert html =~ ~s(data-active-phase="#{active_phase}")
      assert html =~ label
      assert html =~ "Cancel &amp; refund"
      refute html =~ "%"

      {:ok, document} = Floki.parse_document(html)
      assert Floki.find(document, "a button") == []
    end
  end

  test "succeeded generations offer a direct download" do
    prediction = %Prediction{
      id: 43,
      prompt: "finished sticker",
      status: :succeeded,
      sticker_output: "https://example.com/finished.webp",
      score: 0
    }

    html = render_component(&Components.sticker/1, id: "prediction-43", prediction: prediction)

    assert html =~ ~s(data-generation-state="succeeded")
    assert html =~ ~s(href="/sticker/43/download")
    assert html =~ "Download"
    assert html =~ ~s(class="saas-generated-frame)
  end

  test "succeeded generations without output do not offer a broken download" do
    prediction = %Prediction{
      id: 44,
      prompt: "missing finished sticker",
      status: :succeeded,
      sticker_output: nil,
      no_bg_output: nil,
      score: 0
    }

    html = render_component(&Components.sticker/1, id: "prediction-44", prediction: prediction)

    assert html =~ "Preview unavailable"
    refute html =~ ~s(href="/sticker/44/download")
  end

  test "failed and canceled generations explain their refund state" do
    for status <- [:failed, :canceled] do
      prediction = %Prediction{
        id: System.unique_integer([:positive]),
        prompt: "stopped generation",
        status: status,
        model: "text-to-image",
        credit_refunded: true,
        score: 0
      }

      html =
        render_component(&Components.sticker/1,
          id: "prediction-#{prediction.id}",
          prediction: prediction,
          cancel_event: "cancel-generation"
        )

      assert html =~ ~s(data-generation-state="#{status}")
      assert html =~ "Credit returned"
      refute html =~ "Cancel &amp; refund"
      assert html =~ ~s(class="saas-generated-frame)
    end
  end

  test "preview images expose stable loading hints and retry hooks" do
    prediction = %Prediction{
      id: 45,
      prompt: "preview loading hints",
      status: :succeeded,
      sticker_output: "https://example.com/preview.webp",
      score: 0
    }

    eager_html =
      render_component(&Components.sticker/1,
        id: "prediction-45",
        prediction: prediction,
        eager: true
      )

    assert eager_html =~ ~s(phx-hook="PreviewImage")
    assert eager_html =~ ~s(loading="eager")
    assert eager_html =~ ~s(fetchpriority="high")
    assert eager_html =~ ~s(decoding="async")
    assert eager_html =~ ~s(width="1024")
    assert eager_html =~ ~s(height="1024")
    assert eager_html =~ ~s(data-preview-retry)

    css = File.read!("assets/css/app.css")
    assert css =~ "[data-preview-retry][hidden]"
    assert css =~ "[data-preview-error][hidden]"

    lazy_html =
      render_component(&Components.sticker/1, id: "prediction-45-lazy", prediction: prediction)

    assert lazy_html =~ ~s(loading="lazy")
    assert lazy_html =~ ~s(fetchpriority="auto")
  end

  test "active cards expose the slow-state hook and privacy-safe cancel analytics" do
    prediction = %Prediction{
      id: 46,
      prompt: "slow generation",
      status: :processing,
      score: 0
    }

    html =
      render_component(&Components.sticker/1,
        id: "prediction-46",
        prediction: prediction,
        cancel_event: "cancel-generation"
      )

    assert html =~ ~s(phx-hook="GenerationStatus")
    assert html =~ ~s(data-analytics-event="generation_cancel_attempt")
    assert html =~ ~s(data-analytics-context="generation_card")

    {:ok, document} = Floki.parse_document(html)

    [cancel_button] =
      Floki.find(document, "button[data-analytics-event='generation_cancel_attempt']")

    {_tag, attributes, _children} = cancel_button
    refute Enum.any?(attributes, fn {_name, value} -> value =~ prediction.prompt end)
  end
end
