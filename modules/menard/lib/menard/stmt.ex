defmodule Menard.Stmt do
  @moduledoc """
  ONE statement inside a clause body — the last thing that had no verb, so adding a line to a
  function meant editing the file as text.

  Addressed the way a clause is: you name the clause (`name_arity` + `head`), then the statement
  by what is WRITTEN (`Bus.subscribe_habits()`), whitespace-insensitive. A miss lists the
  statements that are there; a match that is ambiguous is refused with line numbers and `nth`,
  never guessed at.

  "Statement" is any addressable node inside the clause, so this reaches a line in a `do` block, a
  step in a `with`, and a `case` arm (`match -> body`) alike — the smallest node whose text
  matches wins, so naming a call does not accidentally select the block containing it.
  """
  alias Menard.Clause
  alias Sourceror.Zipper

  @doc "Insert `code` as a new statement directly after the matched one."
  @spec insert_after(String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def insert_after(source, name_arity, head, match, code, opts \\ []) do
    with {:ok, stmt} <- locate(source, name_arity, head, match, opts) do
      %{end: [line: line, column: col]} = stmt.range
      at = %{start: [line: line, column: col], end: [line: line, column: col]}
      patch(source, at, "\n\n" <> indent_block(code, stmt.indent))
    end
  end

  @doc "Insert `code` as a new statement directly before the matched one."
  @spec insert_before(String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def insert_before(source, name_arity, head, match, code, opts \\ []) do
    with {:ok, stmt} <- locate(source, name_arity, head, match, opts) do
      %{start: [line: line, column: _]} = stmt.range
      at = %{start: [line: line, column: 1], end: [line: line, column: 1]}
      patch(source, at, indent_block(code, stmt.indent) <> "\n\n")
    end
  end

  @doc "Replace the matched statement with `code`."
  @spec replace(String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def replace(source, name_arity, head, match, code, opts \\ []) do
    with {:ok, stmt} <- locate(source, name_arity, head, match, opts) do
      patch(source, stmt.range, reindent(code, stmt.indent))
    end
  end

  @doc "Delete the matched statement, the comment lines glued above it, and a blank line left behind."
  @spec delete(String.t(), String.t(), String.t(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def delete(source, name_arity, head, match, opts \\ []) do
    with {:ok, stmt} <- locate(source, name_arity, head, match, opts) do
      lines = String.split(source, "\n")
      %{start: [line: a, column: _], end: [line: b, column: _]} = stmt.range
      first = a - 1 - comments_above(lines, a - 1)
      last = if Enum.at(lines, b) == "", do: b, else: b - 1

      lines
      |> Enum.with_index()
      |> Enum.reject(fn {_text, i} -> i >= first and i <= last end)
      |> Enum.map_join("\n", &elem(&1, 0))
    end
  end

  @doc """
  The statements this clause holds, as written — what a miss prints, and useful on its own before
  editing one.
  """
  @spec list(String.t(), String.t(), String.t(), keyword()) :: [String.t()] | {:error, String.t()}
  def list(source, name_arity, head, opts \\ []) do
    with {:ok, clause} <- Clause.find(source, name_arity, head, opts) do
      source |> candidates(clause) |> Enum.map(& &1.text)
    end
  end

  # -- locating a statement -------------------------------------------------

  defp locate(source, name_arity, head, match, opts) do
    with {:ok, clause} <- Clause.find(source, name_arity, head, opts) do
      want = Clause.squash(match)
      all = candidates(source, clause)

      case Enum.filter(all, &(Clause.squash(&1.text) == want)) do
        [] ->
          {:error,
           "no statement `#{match}` in #{name_arity} — have: #{Enum.map_join(all, " · ", &"`#{&1.text}`")}"}

        [one] ->
          {:ok, one}

        many ->
          nth(many, match, opts[:nth])
      end
    end
  end

  defp nth(many, match, nil) do
    lines = Enum.map_join(many, ", ", &"line #{line_of(&1)}")

    {:error,
     "#{length(many)} statements match `#{match}` (#{lines}) — say which with --nth 1..#{length(many)}"}
  end

  defp nth(many, match, n) do
    case Enum.at(many, n - 1) do
      nil -> {:error, "--nth #{n} is past the #{length(many)} statements matching `#{match}`"}
      stmt -> {:ok, stmt}
    end
  end

  defp line_of(%{range: %{start: [line: line, column: _]}}), do: line

  # Every node inside the clause that carries a range, smallest first — so naming a call selects
  # the call, not the block around it.
  defp candidates(source, clause) do
    {:ok, ast} = Sourceror.parse_string(source)

    ast
    |> Zipper.zip()
    |> Zipper.traverse([], fn z, acc -> {z, statement_nodes(Zipper.node(z)) ++ acc} end)
    |> elem(1)
    |> Enum.flat_map(&describe(&1, source, clause))
    |> Enum.uniq_by(& &1.range)
    |> Enum.sort_by(&{line_of(&1), &1.span})
  end

  defp describe(node, source, clause) do
    case Sourceror.get_range(node) do
      %{start: [line: a, column: col], end: [line: b, column: _]} = range ->
        if within?(range, clause.range) and not same_as?(range, clause.range) do
          [%{range: range, text: slice(source, range), indent: String.duplicate(" ", col - 1), span: b - a}]
        else
          []
        end

      _no_range ->
        []
    end
  end

  defp within?(%{start: [line: a, column: _], end: [line: b, column: _]}, %{
         start: [line: ca, column: _],
         end: [line: cb, column: _]
       }),
       do: a >= ca and b <= cb

  defp same_as?(%{start: s, end: e}, %{start: s2, end: e2}), do: s == s2 and e == e2

  defp slice(source, %{start: [line: a, column: ca], end: [line: b, column: cb]}) do
    lines = source |> String.split("\n") |> Enum.slice((a - 1)..(b - 1))

    case lines do
      [] ->
        ""

      [one] ->
        String.slice(one, ca - 1, cb - ca)

      many ->
        [first | rest] = many
        {mid, [last]} = Enum.split(rest, length(rest) - 1)
        Enum.join([String.slice(first, (ca - 1)..-1//1) | mid] ++ [String.slice(last, 0, cb - 1)], "\n")
    end
  end

  defp comments_above(lines, i) do
    lines
    |> Enum.take(i)
    |> Enum.reverse()
    |> Enum.take_while(&String.starts_with?(String.trim_leading(&1), "#"))
    |> length()
  end

  defp indent_block(code, indent), do: indent <> reindent(code, indent)

  defp reindent(code, indent) do
    case code |> String.trim() |> String.split("\n") do
      [one] -> one
      [first | rest] -> Enum.join([first | Enum.map(rest, &(indent <> &1))], "\n")
    end
  end

  defp patch(source, range, change),
    do: Sourceror.patch_string(source, [%{range: range, change: change, preserve_indentation: false}])

  # 2+ children means a SEQUENCE of statements. Sourceror also wraps literals in `__block__`, and a
  # one-child block is one of those (`{:ok, :up}`) — a body holding a single statement is reached
  # through its do-block instead.
  defp statement_nodes({:__block__, _meta, children}) when length(children) > 1, do: children

  defp statement_nodes({_call, _meta, args}) when is_list(args) do
    args
    |> List.last()
    |> case do
      [{{:__block__, _m, [key]}, body} | _rest] when key in [:do, :else, :after, :catch, :rescue] ->
        body_statements(body)

      _other ->
        []
    end
  end

  defp statement_nodes(_node), do: []

  # A do-block holds either a `__block__` (many lines, collected above), a list of `->` arms, or one
  # bare expression.
  defp body_statements(arms) when is_list(arms), do: arms
  defp body_statements({:__block__, _meta, _children}), do: []
  defp body_statements(one), do: [one]
end
