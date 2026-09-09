defmodule Menard.Module do
  @moduledoc """
  Whole modules inside a file. `Menard.Clause.insert_at/4` puts a function INTO a module;
  `Menard.Write` replaces a whole file; neither adds a second `defmodule` to a file that already
  has one — which is how the MCP tool components live (six modules in `mcp/tools.ex`), so adding
  one meant appending bytes by hand.
  """

  alias Menard.Clause

  @doc """
  Add `code` — a complete `defmodule` — to the file. It goes after the LAST module, separated by a
  blank line, which is where a reader of a multi-module file looks for the newest one. Refuses
  anything that is not a module, and refuses a name the file already defines.
  """
  @spec add(String.t(), String.t()) :: String.t() | {:error, String.t()}
  def add(source, code) do
    with {:ok, name} <- module_name(code),
         {:ok, ast} <- parse(source),
         :ok <- absent(ast, name) do
      case names(ast) do
        [] -> {:error, "no module in this file to add one after — use `write` for a new file"}
        _any -> append(source, code)
      end
    end
  end

  @doc "The modules a file defines, in source order."
  @spec list(String.t()) :: [String.t()] | {:error, String.t()}
  def list(source) do
    with {:ok, ast} <- parse(source), do: names(ast)
  end

  defp append(source, code) do
    trimmed = String.trim_trailing(source, "\n")
    trimmed <> "\n\n" <> String.trim(code) <> "\n"
  end

  defp absent(ast, name) do
    if name in names(ast),
      do: {:error, "#{name} is already defined in this file"},
      else: :ok
  end

  defp names(ast) do
    ast
    |> Clause.modules()
    |> Enum.map(&elem(&1, 0))
  end

  defp module_name(code) do
    case Sourceror.parse_string(code) do
      {:ok, {:defmodule, _meta, [{:__aliases__, _alias_meta, parts} | _rest]}} ->
        {:ok, Enum.join(parts, ".")}

      {:ok, _other} ->
        {:error, "add takes a whole `defmodule …`, got: #{String.slice(String.trim(code), 0, 40)}"}

      {:error, reason} ->
        {:error, "not parseable — #{inspect(reason)}"}
    end
  end

  defp parse(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, "not parseable — #{inspect(reason)}"}
    end
  end
end
