defmodule Menard.Write do
  @moduledoc """
  Write a WHOLE file — the verb the clause verbs cannot be: a new module has no clause to address
  and no file to patch, so creating one used to mean dropping out of Menard entirely and writing
  raw bytes with no parse check.

  `run/2` refuses anything that does not parse as Elixir, so a syntax error is caught before it
  reaches disk instead of at the next compile. It reports whether the file was created or
  replaced, and the caller formats it with the target project's formatter (`Menard.format/1`).

  The other thing it is for: a rewrite so sweeping that patching is the wrong tool — a fixture
  file, a generated table, a module being replaced outright.
  """

  @doc """
  `code` as the whole content of `path`. Returns `{:ok, :created | :replaced}`, `{:ok, :unchanged}`
  when the bytes already match, or `{:error, message}` if `code` is not parseable Elixir.
  """
  @spec run(String.t(), String.t()) :: {:ok, :created | :replaced | :unchanged} | {:error, String.t()}
  def run(path, code) do
    with {:ok, content} <- checked(path, code) do
      existed? = File.exists?(path)
      previous = if existed?, do: File.read!(path)

      cond do
        previous == content ->
          {:ok, :unchanged}

        true ->
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, content)
          {:ok, if(existed?, do: :replaced, else: :created)}
      end
    end
  end

  # Only .ex/.exs are parsed — Menard writes Elixir, but a fixture next to it may be anything, and
  # refusing to write a .json because it isn't Elixir would be nonsense.
  def checked(path, code) do
    content = if String.ends_with?(code, "\n"), do: code, else: code <> "\n"

    if Path.extname(path) in [".ex", ".exs"] do
      case Code.string_to_quoted(content) do
        {:ok, _ast} ->
          {:ok, content}

        {:error, {meta, message, token}} ->
          {:error, "not parseable at line #{line(meta)}: #{message}#{token}"}

        {:error, reason} ->
          {:error, "not parseable — #{inspect(reason)}"}
      end
    else
      {:ok, content}
    end
  end

  defp line(meta) when is_list(meta), do: Keyword.get(meta, :line, "?")
  defp line(meta) when is_integer(meta), do: meta
  defp line(_meta), do: "?"
end
