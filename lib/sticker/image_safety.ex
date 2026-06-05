defmodule Sticker.ImageSafety do
  require Logger

  @unsafe_terms ~w(UNSAFE unsafe blocked disallowed)

  def review(data_uri) when is_binary(data_uri) do
    if configured?() do
      review_with_openai(data_uri)
    else
      Logger.warning("Image safety review skipped because OPENAI_API_KEY is not configured")
      :ok
    end
  end

  def review(_data_uri), do: {:error, :invalid_image}

  def parse_review_response(body) do
    body
    |> response_text()
    |> decision()
  end

  defp review_with_openai(data_uri) do
    body = %{
      model: System.get_env("OPENAI_SAFETY_MODEL", "gpt-4o-mini"),
      input: [
        %{
          role: "user",
          content: [
            %{
              type: "input_text",
              text:
                "Review this user-uploaded image for a sticker generator. Reply with exactly SAFE or UNSAFE. Mark UNSAFE for nudity, sexual content, minors in unsafe contexts, hate symbols, graphic violence, self-harm, illegal activity, or obvious private/sensitive document content."
            },
            %{type: "input_image", image_url: data_uri}
          ]
        }
      ],
      max_output_tokens: 8
    }

    case Req.post(url: responses_url(), json: body, headers: headers(), receive_timeout: 20_000) do
      {:ok, %{status: status, body: response}} when status in 200..299 ->
        parse_review_response(response)

      {:ok, %{status: status}} ->
        Logger.warning("Image safety review unavailable with HTTP #{status}; allowing upload")
        :ok

      {:error, reason} ->
        Logger.warning("Image safety review unavailable: #{inspect(reason)}; allowing upload")
        :ok
    end
  end

  defp decision(text) when is_binary(text) do
    normalized = String.trim(text)

    cond do
      String.upcase(normalized) == "SAFE" -> :ok
      Enum.any?(@unsafe_terms, &String.contains?(normalized, &1)) -> {:error, :unsafe_image}
      true -> {:error, :review_failed}
    end
  end

  defp decision(_text), do: {:error, :review_failed}

  defp response_text(body) do
    body
    |> collect_text([])
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp collect_text(%{"text" => text}, acc) when is_binary(text), do: [text | acc]

  defp collect_text(map, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {_key, value}, acc -> collect_text(value, acc) end)
  end

  defp collect_text(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_text/2)
  end

  defp collect_text(_value, acc), do: acc

  defp configured?, do: System.get_env("OPENAI_API_KEY") not in [nil, ""]

  defp responses_url do
    System.get_env("OPENAI_BASE_URL", "https://api.openai.com/v1")
    |> String.trim_trailing("/")
    |> Kernel.<>("/responses")
  end

  defp headers do
    [
      {"Authorization", "Bearer #{System.fetch_env!("OPENAI_API_KEY")}"},
      {"Content-Type", "application/json"}
    ]
  end
end
