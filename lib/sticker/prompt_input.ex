defmodule Sticker.PromptInput do
  @moduledoc """
  Validates text-to-sticker input for single and batch generation.
  """

  @max_prompt_length 1_000
  @max_batch_prompts 5

  def parse(prompt, opts \\ [])

  def parse(prompt, opts) when is_binary(prompt) do
    if Keyword.get(opts, :batch?, false) do
      parse_batch(prompt)
    else
      parse_single(prompt)
    end
  end

  def parse(_prompt, _opts), do: {:error, :empty_prompt}

  defp parse_single(prompt) do
    prompt = String.trim(prompt)

    cond do
      prompt == "" -> {:error, :empty_prompt}
      String.length(prompt) > @max_prompt_length -> {:error, :prompt_too_long}
      true -> {:ok, [prompt]}
    end
  end

  defp parse_batch(prompt) do
    prompts =
      prompt
      |> String.split(~r/\R/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    cond do
      prompts == [] ->
        {:error, :empty_prompt}

      length(prompts) > @max_batch_prompts ->
        {:error, :too_many_prompts}

      Enum.any?(prompts, &(String.length(&1) > @max_prompt_length)) ->
        {:error, :prompt_too_long}

      true ->
        {:ok, prompts}
    end
  end
end
