defmodule StickerWeb.PendingPromptIntent do
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  @session_prompt :pending_prompt
  @session_source :pending_prompt_source
  @session_created_at :pending_prompt_created_at
  @max_prompt_length 1_000
  @max_prompts 5
  @ttl_seconds 30 * 60

  def max_prompt_length, do: @max_prompt_length
  def ttl_seconds, do: @ttl_seconds

  def normalize_prompt(prompt) when is_binary(prompt) do
    prompt
    |> String.split(["\n", "\r"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(@max_prompts)
    |> Enum.join("\n")
  end

  def normalize_prompt(_prompt), do: ""

  def validate_prompt(prompt) do
    prompt = normalize_prompt(prompt)

    cond do
      prompt == "" -> {:error, :empty_prompt}
      String.length(prompt) > @max_prompt_length -> {:error, :prompt_too_long}
      true -> {:ok, prompt}
    end
  end

  def put(conn, prompt, source \\ "home_generator") do
    conn
    |> put_session(@session_prompt, prompt)
    |> put_session(@session_source, source)
    |> put_session(@session_created_at, now())
  end

  def store_and_redirect(conn, prompt, source \\ "home_generator") do
    case validate_prompt(prompt) do
      {:ok, normalized_prompt} ->
        conn
        |> put(normalized_prompt, source)
        |> put_flash(:info, "Create an account to generate this sticker with your free credits.")
        |> redirect(to: "/users/register")

      {:error, :empty_prompt} ->
        conn
        |> clear()
        |> put_flash(:error, "Add at least one sticker prompt.")
        |> redirect(to: "/")

      {:error, :prompt_too_long} ->
        conn
        |> clear()
        |> put_flash(:error, "Prompt is too long. Keep it under 1,000 characters.")
        |> redirect(to: "/")
    end
  end

  def peek(conn) do
    with prompt when is_binary(prompt) <- get_session(conn, @session_prompt),
         source when is_binary(source) <- get_session(conn, @session_source),
         created_at when is_integer(created_at) <- get_session(conn, @session_created_at),
         false <- expired?(created_at) do
      {:ok, %{prompt: prompt, source: source, created_at: created_at}}
    else
      true -> {:error, :expired}
      _ -> :none
    end
  end

  def pending?(conn) do
    match?({:ok, _intent}, peek(conn))
  end

  def pop(conn) do
    case peek(conn) do
      {:ok, intent} -> {clear(conn), {:ok, intent}}
      {:error, :expired} -> {clear(conn), {:error, :expired}}
      :none -> {clear(conn), :none}
    end
  end

  def clear(conn) do
    conn
    |> delete_session(@session_prompt)
    |> delete_session(@session_source)
    |> delete_session(@session_created_at)
  end

  def login_redirect_opts(conn) do
    {conn, intent} = pop(conn)

    {conn, redirect_opts(intent)}
  end

  defp redirect_opts({:ok, %{prompt: prompt}}) do
    [
      redirect_to: "/?prompt=#{URI.encode_www_form(prompt)}#generator",
      info: "Your prompt is ready. Click Generate to use 1 free credit."
    ]
  end

  defp redirect_opts({:error, :expired}) do
    [
      redirect_to: "/",
      error: "Your saved prompt expired. Add it again to generate a sticker."
    ]
  end

  defp redirect_opts(:none), do: []

  defp expired?(created_at), do: now() - created_at > @ttl_seconds

  defp now, do: System.system_time(:second)
end
