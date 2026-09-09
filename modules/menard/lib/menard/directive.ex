defmodule Menard.Directive do
  @moduledoc """
  `alias` / `import` / `require` / `use` — added and removed where they belong.

  The insert is trivial; the PLACEMENT is the reason this exists. Elixir has one conventional
  order for a module's directives — `use`, then `import`, then `alias`, then `require`, each
  alphabetised — and Styler enforces it in projects that run it. Dropping a new `alias` at a guessed
  line means the next format pass moves it, so the diff never matches what was written. `add/3`
  puts it in its own block in sorted position, or opens the block in the right place when there
  isn't one: after the `@moduledoc` and after every kind that outranks it.

  An `alias` that is already there is left exactly as written — adding twice is not an error and
  never duplicates a line.
  """

  @kinds [:use, :import, :alias, :require]

  @doc """
  Add `alias Mod` (or `import`/`require`/`use`) to the module. `opts` is the rest of the directive
  as written — `"as: Thing"`, `"only: [pad: 3]"` — or nil. `module` names which module in a file
  that has several; nil takes the only one.
  """
  @spec add(String.t(), atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def add(source, kind, target, opts \\ [])

  def add(_source, kind, _target, _opts) when kind not in @kinds,
    do: {:error, "kind must be one of #{Enum.map_join(@kinds, ", ", &to_string/1)}"}

  def add(source, kind, target, opts) do
    line = directive_line(kind, target, opts[:args])

    with {:ok, ast} <- parse(source),
         {:ok, node} <- Menard.Clause.module_scope(ast, opts[:module]) do
      body = Menard.Clause.module_body(node)

      if exists?(body, kind, target) do
        source
      else
        insert(source, node, body, kind, target, line)
      end
    end
  end

  @doc "Remove `alias Mod` (or import/require/use) and the line it sits on. A miss leaves the source alone."
  @spec remove(String.t(), atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def remove(source, kind, target, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- Menard.Clause.module_scope(ast, opts[:module]) do
      body = Menard.Clause.module_body(node)

      case Enum.find(body, &match(&1, kind, target)) do
        nil -> source
        found -> drop_lines(source, Sourceror.get_range(found))
      end
    end
  end

  @doc "Every directive in the module, as `{kind, \"Mod.Name\"}` in source order — the read half."
  @spec list(String.t(), keyword()) :: [{atom(), String.t()}] | {:error, String.t()}
  def list(source, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- Menard.Clause.module_scope(ast, opts[:module]) do
      node
      |> Menard.Clause.module_body()
      |> Enum.flat_map(fn statement ->
        case directive(statement) do
          nil -> []
          {kind, target} -> [{kind, target}]
        end
      end)
    end
  end

  # -- placement ------------------------------------------------------------

  # In its own block, alphabetically. With no block of this kind yet, after the last directive that
  # outranks it (use > import > alias > require) — and failing that, after the @moduledoc, which is
  # the one thing that is always above every directive.
  defp insert(source, module_node, body, kind, target, line) do
    case Enum.filter(body, &(kind_of(&1) == kind)) do
      [] -> insert_at_block_start(source, module_node, body, kind, line)
      peers -> insert_among(source, peers, target, line)
    end
  end

  defp insert_among(source, peers, target, line) do
    case Enum.find(peers, fn peer -> target_of(peer) > target end) do
      nil -> after_line(source, List.last(peers), line)
      later -> before_line(source, later, line)
    end
  end

  defp insert_at_block_start(source, module_node, body, kind, line) do
    # Only DIRECTIVES rank against each other: a `def` or a `@moduledoc` is not something an alias
    # goes below, and counting them as "outranked" put the alias above the moduledoc.
    directives = Enum.filter(body, &(kind_of(&1) != nil))
    above = Enum.filter(directives, &(rank(kind_of(&1)) < rank(kind)))
    below = Enum.filter(directives, &(rank(kind_of(&1)) > rank(kind)))

    cond do
      above != [] -> after_line(source, List.last(above), line)
      below != [] -> before_line(source, hd(below), line)
      true -> after_preamble(source, module_node, body, line)
    end
  end

  # No directives at all: under the @moduledoc if there is one, else as the module's first line.
  defp after_preamble(source, module_node, body, line) do
    case Enum.find(body, &moduledoc?/1) do
      nil -> open_block(source, module_node, line)
      doc -> after_line(source, doc, line, "\n")
    end
  end

  defp open_block(source, module_node, line) do
    %{start: [line: start, column: col]} = Sourceror.get_range(module_node)
    indent = String.duplicate(" ", col + 1)
    at = %{start: [line: start + 1, column: 1], end: [line: start + 1, column: 1]}
    patch(source, at, indent <> line <> "\n\n")
  end

  defp after_line(source, node, line, gap \\ "") do
    %{start: [line: _, column: col], end: [line: last, column: last_col]} = Sourceror.get_range(node)
    at = %{start: [line: last, column: last_col], end: [line: last, column: last_col]}
    patch(source, at, gap <> "\n" <> String.duplicate(" ", col - 1) <> line)
  end

  defp before_line(source, node, line) do
    %{start: [line: first, column: col]} = Sourceror.get_range(node)
    at = %{start: [line: first, column: 1], end: [line: first, column: 1]}
    patch(source, at, String.duplicate(" ", col - 1) <> line <> "\n")
  end

  defp drop_lines(source, %{start: [line: a, column: _], end: [line: b, column: _]}) do
    source
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.reject(fn {_text, i} -> i >= a - 1 and i <= b - 1 end)
    |> Enum.map_join("\n", &elem(&1, 0))
  end

  # -- reading directives ---------------------------------------------------

  defp directive({kind, _meta, [{:__aliases__, _alias_meta, parts} | _rest]}) when kind in @kinds,
    do: {kind, Enum.join(parts, ".")}

  defp directive(_statement), do: nil

  defp kind_of(statement) do
    case directive(statement) do
      {kind, _target} -> kind
      nil -> nil
    end
  end

  defp target_of(statement) do
    case directive(statement) do
      {_kind, target} -> target
      nil -> ""
    end
  end

  defp match(statement, kind, target), do: directive(statement) == {kind, target}
  defp exists?(body, kind, target), do: Enum.any?(body, &match(&1, kind, target))

  defp moduledoc?({:@, _meta, [{:moduledoc, _inner, _args}]}), do: true
  defp moduledoc?(_statement), do: false

  # The conventional order. A nil kind (anything that is not a directive) sorts after all of them,
  # so a def never counts as something an alias should go below.
  defp rank(kind), do: Enum.find_index(@kinds, &(&1 == kind)) || 99

  defp directive_line(kind, target, nil), do: "#{kind} #{target}"
  defp directive_line(kind, target, ""), do: "#{kind} #{target}"
  defp directive_line(kind, target, args), do: "#{kind} #{target}, #{args}"

  defp parse(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, "not parseable — #{inspect(reason)}"}
    end
  end

  defp patch(source, range, change),
    do: Sourceror.patch_string(source, [%{range: range, change: change, preserve_indentation: false}])
end
