defmodule Sticker.OpenAIImage do
  def generate(prompt) do
    body = %{
      model: model(),
      input: prompt,
      tools: [
        %{
          type: "image_generation",
          size: "1024x1024",
          quality: "medium",
          output_format: "png"
        }
      ],
      tool_choice: %{type: "image_generation"}
    }

    case Req.post(
           url: responses_url(),
           json: body,
           headers: headers(),
           receive_timeout: timeout_ms(),
           connect_options: [timeout: timeout_ms()]
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        parse_response(body)

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def parse_response(%{"output" => output}) when is_list(output) do
    output
    |> Enum.find_value(&image_result/1)
    |> case do
      nil -> {:error, :missing_image_result}
      base64 -> {:ok, base64}
    end
  end

  def parse_response(_body), do: {:error, :missing_image_result}

  defp image_result(%{"type" => "image_generation_call", "result" => result}), do: result
  defp image_result(_item), do: nil

  defp headers do
    [
      {"authorization", "Bearer #{api_key()}"},
      {"content-type", "application/json"}
    ]
  end

  defp responses_url do
    String.trim_trailing(base_url(), "/") <> "/responses"
  end

  defp base_url do
    System.get_env("OPENAI_BASE_URL", "https://api.openai.com/v1")
  end

  defp api_key do
    System.fetch_env!("OPENAI_API_KEY")
  end

  defp model do
    System.get_env("OPENAI_IMAGE_MODEL", "gpt-image-2")
  end

  defp timeout_ms do
    "180000"
    |> then(&System.get_env("OPENAI_IMAGE_TIMEOUT_MS", &1))
    |> String.to_integer()
  end
end
