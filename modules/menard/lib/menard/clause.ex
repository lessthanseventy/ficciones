defmodule Menard.Clause do
  @moduledoc """
  The clause verbs: address one clause of `name/arity` by its head as written — the args, and the
  guard if any (`":b"`, `"x when is_integer(x)"`, parens optional) — then `replace_body/4`,
  `rewrite/4` (the whole clause, head included), `delete/4`, `insert_after/4` or `insert_before/4`.
  Patches from the clause's own source range (Sourceror), so the rest of the file is
  byte-identical. A miss names the clauses that exist. Whitespace in the head pattern is ignored.

  `insert_at/4` is the odd one out: it adds a whole new FUNCTION, which by definition has no
  sibling clause to address. (A new clause of an existing function is `insert_after/4` — name the
  sibling.)
  """

  alias Sourceror.Zipper

  @kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp]

  # Attributes written directly above a clause belong TO that clause, not to the file: delete the
  # clause and leave them behind and they re-attach to whatever follows — "redefining @impl
  # attribute previously set at line N", or a @spec describing a head that no longer exists.
  @attached [:doc, :impl, :spec, :deprecated, :dialyzer]

  @doc "Replace the clause's body with `code` (one line → `, do:` form; more → a `do … end` block)."
  @spec replace_body(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def replace_body(source, name_arity, head, code, opts \\ []) do
    with :ok <- body_only(code),
         {:ok, clause} <- find(source, name_arity, head, opts) do
      Sourceror.patch_string(source, [
        %{range: clause.range, change: clause_text(clause, code), preserve_indentation: false}
      ])
    end
  end

  @doc """
  Replace the WHOLE clause — head included — with `code`, a complete `def …`. The verb for the
  edits `replace_body/4` structurally cannot make: changing the args, adding a guard,
  destructuring a parameter.
  """
  @spec rewrite(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def rewrite(source, name_arity, head, code, opts \\ []) do
    with {:ok, clause} <- find(source, name_arity, head, opts),
         {:ok, _node} <- parse_clause(code) do
      Sourceror.patch_string(source, [
        %{
          range: with_comments_above(source, clause.range, code),
          change: reindent(code, clause.indent),
          preserve_indentation: false
        }
      ])
    end
  end

  @doc "Delete the clause, the comment lines glued above it, and one blank line left behind."
  @spec delete(String.t(), String.t(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def delete(source, name_arity, head, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, %{range: %{end: [line: b, column: _]}} = clause} <- find(source, name_arity, head, opts) do
      lines = String.split(source, "\n")
      # The clause starts at its first ATTACHED ATTRIBUTE, not at its `def` — see @attached.
      a = attrs_start(ast, clause.range)
      first = a - 1 - comment_lines_above(lines, a - 1)
      last = b - 1

      last =
        if Enum.at(lines, last + 1) == "" and (first == 0 or Enum.at(lines, first - 1) == ""),
          do: last + 1,
          else: last

      lines
      |> Enum.with_index()
      |> Enum.reject(fn {_l, i} -> i >= first and i <= last end)
      |> Enum.map_join("\n", &elem(&1, 0))
    end
  end

  @doc "Insert `code` as a new clause on the line after the addressed one, at its indent."
  @spec insert_after(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def insert_after(source, name_arity, head, code, opts \\ []) do
    with {:ok, %{range: %{end: [line: b, column: c]}, indent: indent}} <- find(source, name_arity, head, opts) do
      body = code |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))
      at = %{start: [line: b, column: c], end: [line: b, column: c]}
      Sourceror.patch_string(source, [%{range: at, change: "\n" <> body, preserve_indentation: false}])
    end
  end

  @doc "Insert `code` as a new clause on the line before the addressed one, at its indent."
  @spec insert_before(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def insert_before(source, name_arity, head, code, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, %{range: range, indent: indent}} <- find(source, name_arity, head, opts) do
      lines = String.split(source, "\n")
      # Above the clause's @doc/@spec too, the block `delete/4` takes: a @doc attaches to whatever
      # definition FOLLOWS it, so landing between the two hands the doc to the new code.
      a = attrs_start(ast, range)
      a = a - comment_lines_above(lines, a - 1)
      body = code |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))
      at = %{start: [line: a, column: 1], end: [line: a, column: 1]}
      Sourceror.patch_string(source, [%{range: at, change: body <> "\n", preserve_indentation: false}])
    end
  end

  @doc """
  Insert `code` where there is NO sibling clause to anchor to — a whole new function, which
  `insert_after/4` cannot address because it takes an existing head. (A new *clause* of a function
  that already exists is still `insert_after/4`: name its sibling.)

  `where` is usually nil, and then the code decides: a `defp` lands after the module's last
  private function, a `def` after its last public one — where a reader goes looking for each.
  `:top`/`:bottom` override that with the module's first/last definition; an empty module takes
  the code just inside. `module` is `"Mod.Name"`, or nil in a file with exactly one module.
  """
  @spec insert_at(String.t(), String.t() | nil, :top | :bottom | String.t() | nil, String.t()) ::
          String.t() | {:error, String.t()}
  def insert_at(source, module, where, code) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- module_scope(ast, module) do
      case anchor(definitions(node), normalize_where(where), code) do
        nil -> insert_inside_empty(source, node, code)
        {sibling, side} -> anchor_insert(source, sibling, side, code)
      end
    end
  end

  @doc """
  Flip a function's visibility — EVERY clause of it, in one patch. `def`↔`defp`, keeping the family
  (`defmacro`↔`defmacrop`, `defguard`↔`defguardp`).

  One verb rather than a rewrite per clause because a half-flipped function does not compile: the
  clauses of one name/arity must agree, so doing them one at a time leaves the module broken in
  between and unrecoverable if you stop. Going private also drops an attached `@doc` — Elixir
  discards docs on a private function and warns, which is a failed build under
  --warnings-as-errors.
  """
  @spec visibility(String.t(), String.t(), :public | :private) :: String.t() | {:error, String.t()}
  def visibility(source, name_arity, want) when want in [:public, :private] do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity) do
      case clauses(scope, name, arity) do
        [] -> {:error, "no #{name}/#{arity} in this file"}
        found -> source |> flip(found, want) |> drop_docs(name_arity, want)
      end
    end
  end

  # Where a new function goes. `:top`/`:bottom` are the module first/last definition, asked for
  # explicitly; with neither, the CODE says — a `defp` belongs after the last private function, a
  # `def` after the last public one, which is where a reader goes looking for it. Nothing to anchor
  # to at all is nil, and the caller puts it inside the bare module.
  defp anchor([], _where, _code), do: nil
  defp anchor(defs, :top, _code), do: {hd(defs), :top}
  defp anchor(defs, :bottom, _code), do: {List.last(defs), :bottom}

  defp anchor(defs, nil, code) do
    private? = private_kind?(kind_of(code))
    same_kind = Enum.filter(defs, &(private_kind?(node_kind(&1)) == private?))
    {List.last(same_kind) || List.last(defs), :bottom}
  end

  defp normalize_where(where) when where in [:top, :bottom], do: where
  defp normalize_where("top"), do: :top
  defp normalize_where("bottom"), do: :bottom
  defp normalize_where(_none), do: nil

  defp private_kind?(kind), do: kind in [:defp, :defmacrop, :defguardp]

  # The kind the code DEFINES — the last node, so a `@doc`/`@spec` written above the def is not
  # mistaken for the thing being inserted.
  defp kind_of(code) do
    case Sourceror.parse_string(code) do
      {:ok, {:__block__, _meta, nodes}} -> nodes |> List.last() |> node_kind()
      {:ok, node} -> node_kind(node)
      _ -> nil
    end
  end

  defp node_kind({kind, _meta, _args}) when is_atom(kind), do: kind
  defp node_kind(_node), do: nil

  # A new FUNCTION, unlike a new clause of an existing one, is separated from its neighbour by a
  # blank line — clauses of one function are glued, functions are not.
  defp anchor_insert(source, node, :top, code) do
    %{start: [line: line, column: col]} = Sourceror.get_range(node)
    at = %{start: [line: line, column: 1], end: [line: line, column: 1]}
    patch(source, at, indented(code, col) <> "\n\n")
  end

  defp anchor_insert(source, node, :bottom, code) do
    %{start: [line: _, column: col], end: [line: line, column: last_col]} = Sourceror.get_range(node)
    at = %{start: [line: line, column: last_col], end: [line: line, column: last_col]}
    patch(source, at, "\n\n" <> indented(code, col))
  end

  # Nothing to anchor to at all: just inside the module's own `end`, one level in from it.
  defp insert_inside_empty(source, node, code) do
    %{start: [line: _, column: col], end: [line: line, column: _]} = Sourceror.get_range(node)
    at = %{start: [line: line, column: 1], end: [line: line, column: 1]}
    patch(source, at, indented(code, col + 2) <> "\n")
  end

  defp indented(code, col) do
    indent = String.duplicate(" ", col - 1)
    code |> String.trim() |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))
  end

  defp patch(source, range, change),
    do: Sourceror.patch_string(source, [%{range: range, change: change, preserve_indentation: false}])

  # -- locating a clause ----------------------------------------------------

  @doc """
  Locate one clause: `%{kind, name, args, guard, head_text, range, indent}`, or an error naming the
  heads that exist. Public so `Menard.Stmt` addresses a statement the same way — inside the clause
  you named, by what is written.
  """
  def find(source, name_arity, head, opts) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity) do
      clauses = clauses(scope, name, arity)
      want = wanted_head(head, name, arity)

      case Enum.filter(clauses, &(squash(&1.head_text) == want)) do
        [] -> {:error, "no clause #{name}/#{arity} with head `#{head}` — have: #{heads(clauses)}"}
        [one] -> {:ok, one}
        many -> pick_nth(many, name, arity, head, opts[:nth])
      end
    end
  end

  # A zero-arity clause has no head, so the name is what a caller would write. Arity 0 only: at
  # arity 1 `style` is an ARGUMENT.
  defp wanted_head(head, name, 0) do
    n = to_string(name)

    if squash(head) in ["", squash(n), squash("#{n}()"), squash("def #{n}"), squash("def #{n}()")],
      do: "",
      else: squash(head)
  end

  defp wanted_head(head, _name, _arity), do: squash(head)

  # Acting on "the first" silently is how a delete eats the clause that was just written, so an
  # ambiguous head is refused and `--nth` is the way to mean one of them.
  defp pick_nth(many, name, arity, head, nil) do
    lines = Enum.map_join(many, ", ", fn c -> "line #{start_line_of(c)}" end)

    {:error,
     "#{length(many)} clauses of #{name}/#{arity} share the head `#{head}` (#{lines}) — " <>
       "say which with --nth 1..#{length(many)}"}
  end

  defp pick_nth(many, name, arity, head, nth) do
    case Enum.at(many, nth - 1) do
      nil ->
        {:error, "--nth #{nth} is past the #{length(many)} clauses of #{name}/#{arity} with head `#{head}`"}

      clause ->
        {:ok, clause}
    end
  end

  defp start_line_of(%{range: %{start: [line: line, column: _]}}), do: line
  defp start_line_of(_clause), do: "?"

  defp parse(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, "not parseable — #{inspect(reason)}"}
    end
  end

  # `code` must BE a clause: a bare expression would silently replace a def with an expression and
  # leave the module a compile error, which is the one thing these verbs must never do.
  # A clause and the comment glued above it are one unit to a reader, so `rewrite` takes both: the
  # comment lines split off for the parse check and patch back in with the clause.
  defp parse_clause(code) do
    {_comments, body} = split_leading_comments(code)

    case Sourceror.parse_string(body) do
      {:ok, {kind, _meta, _args} = node} when kind in @kinds ->
        {:ok, node}

      {:ok, _other} ->
        {:error, "rewrite needs a whole clause (`def …`), got: #{String.slice(String.trim(body), 0, 40)}"}

      {:error, reason} ->
        {:error, "not parseable — #{inspect(reason)}"}
    end
  end

  # Only a leading run that ENDS at the first real line counts, so a comment inside a body stays put.
  defp split_leading_comments(code) do
    lines = String.split(code, "\n")
    {lead, rest} = Enum.split_while(lines, &comment_or_blank?/1)

    {Enum.join(lead, "\n"), Enum.join(rest, "\n")}
  end

  defp comment_or_blank?(line) do
    trimmed = String.trim(line)
    trimmed == "" or String.starts_with?(trimmed, "#")
  end

  # The subtree to search: the named module's `defmodule`, or — unqualified — the whole file,
  # refused when more than one module in it defines name/arity (an edit must never land in the
  # wrong module silently).
  defp scope(ast, nil, name, arity) do
    case Enum.filter(modules(ast), fn {_mod, node} -> clauses(node, name, arity) != [] end) do
      [_, _ | _] = many ->
        {:error,
         "#{name}/#{arity} is defined in #{Enum.map_join(many, ", ", &elem(&1, 0))} — qualify it as Mod.#{name}/#{arity}"}

      _ ->
        {:ok, ast}
    end
  end

  defp scope(ast, mod, _name, _arity) do
    case List.keyfind(modules(ast), mod, 0) do
      {^mod, node} ->
        {:ok, node}

      nil ->
        {:error, "no module #{mod} in this file — have: #{Enum.map_join(modules(ast), ", ", &elem(&1, 0))}"}
    end
  end

  # Every `defmodule` in the file as `{"Full.Name", node}` (nested modules by their written name).
  def modules(ast) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse([], fn z, acc ->
      case Zipper.node(z) do
        {:defmodule, _, [{:__aliases__, _, parts} | _]} = node -> {z, acc ++ [{Enum.join(parts, "."), node}]}
        _ -> {z, acc}
      end
    end)
    |> elem(1)
  end

  # The module to act in: named, or — unnamed — the file's one module. Several unnamed is refused,
  # the same discipline as an unqualified name/arity two modules define.
  @doc false
  def module_scope(ast, nil) do
    case modules(ast) do
      [{_name, node}] -> {:ok, node}
      [] -> {:error, "no module in this file"}
      many -> {:error, "several modules here — name one: #{Enum.map_join(many, ", ", &elem(&1, 0))}"}
    end
  end

  def module_scope(ast, module) do
    case List.keyfind(modules(ast), module, 0) do
      {^module, node} ->
        {:ok, node}

      nil ->
        {:error,
         "no module #{module} in this file — have: #{Enum.map_join(modules(ast), ", ", &elem(&1, 0))}"}
    end
  end

  # The module's own top-level definitions, in source order — a def nested inside another is not one.
  defp definitions(node) do
    node |> module_body() |> Enum.filter(&match?({kind, _meta, _args} when kind in @kinds, &1))
  end

  @doc false
  def module_body({:defmodule, _, [_alias, [{_do, {:__block__, _, statements}}]]}), do: statements
  def module_body({:defmodule, _, [_alias, [{_do, statement}]]}), do: [statement]
  def module_body(_node), do: []

  defp parse_name_arity(spec) do
    with [path, arity] <- String.split(spec, "/"),
         {arity, ""} <- Integer.parse(arity) do
      # `Mod.Sub.fun/2` scopes the search to that module; `fun/2` searches the whole file
      {mod, [name]} = path |> String.split(".") |> Enum.split(-1)
      {:ok, {if(mod == [], do: nil, else: Enum.join(mod, ".")), String.to_atom(name), arity}}
    else
      _ -> {:error, "expected [Mod.]name/arity, got #{inspect(spec)}"}
    end
  end

  defp clauses(ast, name, arity) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse([], fn z, acc -> {z, acc ++ matching(Zipper.node(z), name, arity)} end)
    |> elem(1)
  end

  defp matching({kind, _meta, [head | _]} = node, name, arity) when kind in @kinds do
    if name_arity(head) == {name, arity}, do: [clause(kind, name, head, node)], else: []
  end

  defp matching(_node, _name, _arity), do: []

  defp clause(kind, name, head, node) do
    %{start: [line: _, column: col]} = range = Sourceror.get_range(node)
    {args, guard} = split_head(head)

    %{
      kind: kind,
      name: name,
      args: args,
      guard: guard,
      head_text: if(guard, do: args <> " when " <> guard, else: args),
      range: range,
      indent: String.duplicate(" ", col - 1)
    }
  end

  defp name_arity({:when, _, [call | _]}), do: name_arity(call)
  defp name_arity({name, _, args}) when is_list(args), do: {name, length(args)}
  defp name_arity({name, _, _}), do: {name, 0}

  # The head as written: `{args_text, guard_text | nil}`.
  defp split_head({:when, _, [call, guard]}), do: {elem(split_head(call), 0), Sourceror.to_string(guard)}

  defp split_head({_name, _, args}) when is_list(args),
    do: {Enum.map_join(args, ", ", &Sourceror.to_string/1), nil}

  defp split_head(_head), do: {"", nil}

  def squash(text), do: text |> String.trim() |> unwrap_parens() |> String.replace(~r/\s+/, "")
  # `(dir, args)` IS how a head is written, so accept the parens people copy off the def line —
  # strip one pair when it actually wraps the whole head (`(a), (b)` is two args, not a wrapper,
  # and stays as it is).
  defp unwrap_parens("(" <> _rest = text) do
    case matching_close(text) do
      {:close, i} ->
        inner = text |> String.slice(1, i - 1) |> String.trim()
        rest = text |> String.slice((i + 1)..-1//1) |> String.trim()

        cond do
          # `(dir, args)` — the parens wrap the whole head
          rest == "" -> inner
          # `(x) when is_integer(x)` — they wrap the args, and the guard follows
          String.starts_with?(rest, "when ") -> inner <> " " <> rest
          # `(a), (b)` — not a wrapper at all; leave it exactly as given
          true -> text
        end

      :unclosed ->
        text
    end
  end

  defp unwrap_parens(text), do: text

  # The index of the `)` closing the `(` at position 0 — how far the leading paren actually reaches.
  defp matching_close(text) do
    text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reduce_while(0, fn
      {"(", _i}, depth -> {:cont, depth + 1}
      {")", i}, 1 -> {:halt, {:close, i}}
      {")", _i}, depth -> {:cont, depth - 1}
      {_char, _i}, depth -> {:cont, depth}
    end)
    |> case do
      {:close, i} -> {:close, i}
      _depth -> :unclosed
    end
  end

  defp heads([]), do: "none"

  defp heads(clauses) do
    Enum.map_join(clauses, " · ", fn
      %{head_text: ""} -> "`` (zero-arity — pass an empty head, or the name)"
      c -> "`#{c.head_text}`"
    end)
  end

  # CODE here is the BODY, and a whole `def` nests inside itself — `def bg, do: def(bg, do: X)`
  # parses, so only the compiler would object.
  defp body_only(code) do
    if Regex.match?(~r/^\s*(def|defp|defmacro|defmacrop)\s/, code) do
      {:error,
       "CODE is the clause BODY here, and this looks like a whole clause — use `rewrite`, which replaces the head too"}
    else
      :ok
    end
  end

  # -- text -----------------------------------------------------------------

  defp clause_text(%{kind: kind, name: name, args: args, guard: guard, indent: indent}, code) do
    # zero arity is written WITHOUT parens in Elixir, and rewriting `def bg` as `def bg()` is a
    # diff on a line the caller did not ask to change
    head =
      if String.trim(args) == "", do: "#{kind} #{name}", else: "#{kind} #{name}(#{args})"

    head = head <> if(guard, do: " when " <> guard, else: "")

    case String.split(String.trim(code), "\n") do
      [one] -> head <> ", do: " <> one
      many -> Enum.join([head <> " do" | Enum.map(many, &(indent <> "  " <> &1))] ++ [indent <> "end"], "\n")
    end
  end

  # A rewrite patches AT the clause's own column, so the first line carries no indent of its own and
  # every later line is shifted out to it.
  defp reindent(code, indent) do
    case code |> String.trim() |> String.split("\n") do
      [one] -> one
      [first | rest] -> Enum.join([first | Enum.map(rest, &(indent <> &1))], "\n")
    end
  end

  defp comment_lines_above(lines, i) do
    lines
    |> Enum.take(i)
    |> Enum.reverse()
    |> Enum.take_while(&String.starts_with?(String.trim_leading(&1), "#"))
    |> length()
  end

  # The line a clause really starts on: its first ATTACHED attribute, walking back over the
  # contiguous `@doc`/`@impl`/`@spec` siblings written above it, else the `def` line itself. Only
  # CONTIGUOUS ones count, so deleting the middle clause of a function takes the `@impl` written
  # above THAT clause and leaves the `@doc` written above the first one alone.
  defp attrs_start(ast, %{start: [line: line, column: _]}) do
    Enum.reduce(module_bodies(ast), line, fn statements, acc ->
      case Enum.find_index(statements, &(start_line(&1) == line)) do
        nil ->
          acc

        i ->
          statements
          |> Enum.take(i)
          |> Enum.reverse()
          |> Enum.take_while(&attached_attr?/1)
          |> Enum.map(&start_line/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.min(fn -> acc end)
      end
    end)
  end

  defp module_bodies(ast), do: Enum.map(modules(ast), fn {_name, node} -> module_body(node) end)

  defp start_line(node) do
    case Sourceror.get_range(node) do
      %{start: [line: line, column: _]} -> line
      _ -> nil
    end
  end

  defp attached_attr?({:@, _meta, [{name, _inner, _args}]}) when is_atom(name), do: name in @attached
  defp attached_attr?(_node), do: false

  # The `def` keyword is the first token of the clause's own range, so each flip is a patch of
  # exactly that word — every other byte of every clause is untouched.
  defp flip(source, clauses, want) do
    patches =
      Enum.flat_map(clauses, fn clause ->
        new = kind_for(clause.kind, want)
        %{start: [line: line, column: col]} = clause.range

        if new == clause.kind do
          []
        else
          [
            %{
              range: %{
                start: [line: line, column: col],
                end: [line: line, column: col + String.length(Atom.to_string(clause.kind))]
              },
              change: Atom.to_string(new),
              preserve_indentation: false
            }
          ]
        end
      end)

    if patches == [], do: source, else: Sourceror.patch_string(source, patches)
  end

  defp kind_for(:def, :private), do: :defp
  defp kind_for(:defmacro, :private), do: :defmacrop
  defp kind_for(:defguard, :private), do: :defguardp
  defp kind_for(:defp, :public), do: :def
  defp kind_for(:defmacrop, :public), do: :defmacro
  defp kind_for(:defguardp, :public), do: :defguard
  defp kind_for(kind, _want), do: kind

  # A `@doc` above a now-private clause is discarded by Elixir with a warning, so it goes with the
  # flip. `@spec` and `@impl` stay — both are legal on a defp.
  defp drop_docs(source, _name_arity, :public), do: source

  defp drop_docs(source, name_arity, :private) do
    with {:ok, {mod, name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, scope} <- scope(ast, mod, name, arity) do
      doomed =
        scope
        |> clauses(name, arity)
        |> Enum.flat_map(&doc_lines(ast, &1.range))
        |> MapSet.new()

      if Enum.empty?(doomed) do
        source
      else
        source
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.reject(fn {_text, line} -> MapSet.member?(doomed, line) end)
        |> Enum.map_join("\n", &elem(&1, 0))
      end
    else
      _ -> source
    end
  end

  # Every line of the `@doc` attached above this clause (a heredoc doc spans several).
  defp doc_lines(ast, %{start: [line: line, column: _]}) do
    Enum.flat_map(module_bodies(ast), fn statements ->
      case Enum.find_index(statements, &(start_line(&1) == line)) do
        nil ->
          []

        i ->
          statements
          |> Enum.take(i)
          |> Enum.reverse()
          |> Enum.take_while(&attached_attr?/1)
          |> Enum.filter(&doc_attr?/1)
          |> Enum.flat_map(fn node ->
            %{start: [line: a, column: _], end: [line: b, column: _]} = Sourceror.get_range(node)
            Enum.to_list(a..b)
          end)
      end
    end)
  end

  defp doc_attr?({:@, _meta, [{:doc, _inner, _args}]}), do: true
  defp doc_attr?(_node), do: false

  @doc """
  Set (or replace) the `@doc` attached to a clause. A docstring is a string literal on an
  attribute, so no other verb reaches it — editing one meant editing the file as text. `text` is
  the prose, not the `@doc` line: it is wrapped in a heredoc here. `nil` deletes the attribute.
  """
  @spec doc(String.t(), String.t(), String.t(), String.t() | nil, keyword()) ::
          String.t() | {:error, String.t()}
  def doc(source, name_arity, head, text, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, clause} <- find(source, name_arity, head, opts) do
      existing = attached_doc_lines(ast, clause.range)
      rendered = if is_nil(text), do: nil, else: clause.indent <> doc_text(text, clause.indent)

      case {existing, text} do
        {nil, nil} -> source
        {nil, _} -> insert_at_line(source, doc_start(ast, clause.range), rendered)
        {{a, b}, nil} -> delete_line_range(source, a, b)
        {{a, b}, _} -> replace_line_range(source, a, b, rendered)
      end
    end
  end

  # Where a NEW @doc goes: above the clause's attached attributes, so it lands over @impl/@spec
  # rather than between them and the def.
  defp doc_start(ast, range), do: attrs_start(ast, range)

  defp doc_text(text, indent) do
    pad = if is_integer(indent), do: String.duplicate(" ", indent), else: indent

    body =
      text
      |> String.trim_trailing()
      |> String.split("\n")
      |> Enum.map_join("\n", &if(&1 == "", do: "", else: pad <> &1))

    "@doc \"\"\"\n" <> body <> "\n" <> pad <> "\"\"\""
  end

  defp insert_at_line(source, line, text) do
    lines = String.split(source, "\n")
    {before, rest} = Enum.split(lines, line - 1)

    Enum.join(before ++ [text] ++ rest, "\n")
  end

  # When the replacement carries its own leading comment, the range grows upward to swallow the
  # comment already glued above the clause — otherwise the old why and the new one both survive,
  # which is worse than the two-step edit this was meant to replace.
  defp with_comments_above(source, range, code) do
    case split_leading_comments(code) do
      {"", _body} ->
        range

      {_lead, _body} ->
        %{start: [line: line, column: _]} = range
        lines = String.split(source, "\n")
        above = comment_lines_above(lines, line - 1)

        put_in(range.start, line: line - above, column: 1)
    end
  end

  @doc """
  Set, replace or delete the comment block glued above a clause — the load-bearing `why` that sits
  over a `def`. `text` is prose, one line per line; `#` is added (and an existing one tolerated, so
  pasting a block back is idempotent). A blank line becomes a bare `#`. `nil` deletes the block.

  `rewrite` can carry a comment too, but only by restating the whole clause; this changes the
  comment and nothing else.
  """
  @spec comment(String.t(), String.t(), String.t(), String.t() | nil, keyword()) ::
          String.t() | {:error, String.t()}
  def comment(source, name_arity, head, text, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, clause} <- find(source, name_arity, head, opts) do
      lines = String.split(source, "\n")
      # The comment sits above the clause's ATTACHED attributes, not above the `def` — a `@doc`
      # written between them would otherwise orphan the comment from what it explains.
      anchor = attrs_start(ast, clause.range)
      above = comment_lines_above(lines, anchor - 1)

      case {above, text} do
        {0, nil} -> source
        {0, _} -> insert_at_line(source, anchor, comment_text(text, clause.indent))
        {n, nil} -> delete_line_range(source, anchor - n, anchor - 1)
        {n, _} -> replace_line_range(source, anchor - n, anchor - 1, comment_text(text, clause.indent))
      end
    end
  end

  defp comment_text(text, indent) do
    pad = if is_integer(indent), do: String.duplicate(" ", indent), else: indent

    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      case line |> String.trim() |> String.replace_prefix("#", "") |> String.trim_leading() do
        "" -> pad <> "#"
        body -> pad <> "# " <> body
      end
    end)
  end

  defp delete_line_range(source, a, b) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {_text, i} -> i >= a and i <= b end)
    |> Enum.map_join("\n", &elem(&1, 0))
  end

  defp replace_line_range(source, a, b, text) do
    lines = String.split(source, "\n")

    (Enum.take(lines, a - 1) ++ [text] ++ Enum.drop(lines, b))
    |> Enum.join("\n")
  end

  defp attached_doc_lines(ast, %{start: [line: line, column: _]}) do
    Enum.reduce(module_bodies(ast), nil, fn statements, acc ->
      case Enum.find_index(statements, &(start_line(&1) == line)) do
        nil ->
          acc

        i ->
          statements
          |> Enum.take(i)
          |> Enum.reverse()
          |> Enum.take_while(&attached_attr?/1)
          |> Enum.find(&doc_attr?/1)
          |> case do
            nil -> acc
            node -> line_span(node)
          end
      end
    end)
  end

  # LINE numbers, not the node range: a heredoc `@doc` ends at a column Sourceror places past the
  # closing quotes, and patching that range swallowed the newline after it (`"""  @spec`). An
  # attribute owns whole lines, so whole lines are what gets replaced.
  defp line_span(node) do
    %{start: [line: a, column: _], end: [line: b, column: _]} = Sourceror.get_range(node)
    {a, b}
  end
end
