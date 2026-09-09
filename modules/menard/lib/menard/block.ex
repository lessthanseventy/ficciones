defmodule Menard.Block do
  @moduledoc """
  The body of a macro's `do` block — `schema do … end`, `describe "…" do`, `test "…" do`,
  `setup do`. Not a clause, so no clause verb reaches one; the MCP tools' `schema` blocks were
  edited by hand for exactly this reason.

  Addressed by the macro's NAME, and by its `label` when the macro takes a string first — which is
  what makes `describe "the retired leader"` and `test "…"` addressable at all. Several blocks
  sharing a name and no label given is refused with their labels, never guessed at.
  """

  alias Menard.Clause
  alias Sourceror.Zipper

  @doc "Replace the block's body with `code`, keeping the `name … do` line and the `end`."
  @spec replace(String.t(), String.t() | atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def replace(source, name, code, opts \\ []) do
    with {:ok, node} <- one(source, name, opts) do
      %{start: [line: _, column: col]} = Sourceror.get_range(node)
      %{start: [line: a, column: _], end: [line: b, column: _]} = body_range(node)
      indent = String.duplicate(" ", col + 1)
      written = code |> String.trim() |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))

      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn
        {_text, ^a} -> [written]
        {_text, line} when line > a and line <= b -> []
        {text, _line} -> [text]
      end)
      |> Enum.join("\n")
    end
  end

  @doc """
  Add a new `name "label" do … end` block. Placement, in order: at the END of the block named by
  `in:` (a `describe`, matched by its label) — which is where a new test goes; else after the last
  sibling block of the same name; else at the end of the module.
  """
  @spec add(String.t(), String.t() | atom(), String.t() | nil, String.t(), keyword()) ::
          String.t() | {:error, String.t()}
  def add(source, name, label, body, opts \\ []) do
    with {:ok, ast} <- parse(source),
         {:ok, module} <- Clause.module_scope(ast, opts[:module]),
         {:ok, all} <- blocks(source, opts),
         {:ok, where, anchor} <- placement(all, module, to_atom(name), opts[:in]) do
      place(source, where, anchor, render(to_atom(name), label, body))
    end
  end

  # `in:` names a parent to append inside; without it a sibling of the same name is the anchor, and
  # with neither the module itself is.
  defp placement(all, _module, _name, parent) when is_binary(parent) do
    case Enum.filter(all, &(label(&1) == parent)) do
      [node] -> {:ok, :inside, node}
      [] -> {:error, "no block labelled #{inspect(parent)} here"}
      many -> {:error, "#{length(many)} blocks labelled #{inspect(parent)} — cannot tell which"}
    end
  end

  defp placement(all, module, name, _none) do
    case Enum.filter(all, &(call_name(&1) == name)) do
      [] -> {:ok, :inside, module}
      siblings -> {:ok, :after, List.last(siblings)}
    end
  end

  # Inside: on the line before the block's own `end`, one level in. After: below the anchor, at the
  # anchor's own column. Both leave a blank line, the way blocks are separated everywhere else.
  defp place(source, :inside, node, text) do
    %{start: [line: _, column: col], end: [line: last, column: _]} = Sourceror.get_range(node)
    at = %{start: [line: last, column: 1], end: [line: last, column: 1]}
    patch(source, at, "\n" <> indented(text, col + 2) <> "\n")
  end

  defp place(source, :after, node, text) do
    %{start: [line: _, column: col], end: [line: last, column: last_col]} = Sourceror.get_range(node)
    at = %{start: [line: last, column: last_col], end: [line: last, column: last_col]}
    patch(source, at, "\n\n" <> indented(text, col))
  end

  defp render(name, nil, body), do: "#{name} do\n" <> indented(body, 3) <> "\nend"
  defp render(name, label, body), do: "#{name} #{inspect(label)} do\n" <> indented(body, 3) <> "\nend"

  defp indented(text, col) do
    indent = String.duplicate(" ", col - 1)
    text |> String.trim() |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))
  end

  defp patch(source, range, change),
    do: Sourceror.patch_string(source, [%{range: range, change: change, preserve_indentation: false}])

  @doc "The block's body exactly as written."
  @spec get(String.t(), String.t() | atom(), keyword()) :: String.t() | {:error, String.t()}
  def get(source, name, opts \\ []) do
    with {:ok, node} <- one(source, name, opts) do
      %{start: [line: a, column: _], end: [line: b, column: _]} = body_range(node)

      source
      |> String.split("\n")
      |> Enum.slice((a - 1)..(b - 1))
      |> Enum.join("\n")
    end
  end

  @doc "Every `do`-block macro call in the module, as `{name, label | nil, line}` in source order."
  @spec list(String.t(), keyword()) :: [{atom(), String.t() | nil, pos_integer()}] | {:error, String.t()}
  def list(source, opts \\ []) do
    with {:ok, blocks} <- blocks(source, opts) do
      Enum.map(blocks, fn node -> {call_name(node), label(node), start_line(node)} end)
    end
  end

  # -- locating ------------------------------------------------------------

  defp one(source, name, opts) do
    want = to_atom(name)
    wanted_label = opts[:label]

    with {:ok, blocks} <- blocks(source, opts) do
      blocks
      |> Enum.filter(&(call_name(&1) == want))
      |> Enum.filter(fn node -> is_nil(wanted_label) or label(node) == wanted_label end)
      |> pick(want, wanted_label)
    end
  end

  defp pick([node], _want, _label), do: {:ok, node}

  defp pick([], want, nil), do: {:error, "no `#{want} do` block here"}
  defp pick([], want, label), do: {:error, "no `#{want} #{inspect(label)} do` block here"}

  defp pick(many, want, _label) do
    labels = Enum.map_join(many, " · ", fn node -> inspect(label(node)) <> " (line #{start_line(node)})" end)
    {:error, "#{length(many)} `#{want}` blocks here — name one with a label: #{labels}"}
  end

  # Every macro call in the module that carries a `do` block, at any depth: a `test` lives inside a
  # `describe`, so a top-level-only walk would miss most of them.
  defp blocks(source, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, module} <- Clause.module_scope(ast, opts[:module]) do
      found =
        module
        |> Zipper.zip()
        |> Zipper.traverse([], fn zipper, acc ->
          node = Zipper.node(zipper)
          if block?(node), do: {zipper, acc ++ [node]}, else: {zipper, acc}
        end)
        |> elem(1)

      {:ok, found}
    end
  end

  # -- shapes --------------------------------------------------------------

  # A macro call whose last argument is a `do` keyword list. `defmodule` and the def kinds are
  # excluded: those have their own verbs, and a module is not a block you replace the body of.
  defp block?({name, _meta, args}) when is_atom(name) and is_list(args) and args != [] do
    name not in [:defmodule, :def, :defp, :defmacro, :defmacrop, :defguard, :defguardp] and
      has_do?(List.last(args))
  end

  defp block?(_node), do: false

  defp has_do?(args) when is_list(args), do: Enum.any?(args, &do_key?/1)
  defp has_do?(_args), do: false

  defp do_key?({{:__block__, _meta, [:do]}, _body}), do: true
  defp do_key?({:do, _body}), do: true
  defp do_key?(_pair), do: false

  defp call_name({name, _meta, _args}), do: name

  # The first string argument, which is how `describe "…"` and `test "…"` are told apart.
  defp label({_name, _meta, args}) do
    Enum.find_value(args, fn
      {:__block__, _meta, [text]} when is_binary(text) -> text
      text when is_binary(text) -> text
      _other -> nil
    end)
  end

  defp body_range({_name, _meta, args}) do
    args
    |> List.last()
    |> Enum.find_value(fn
      {{:__block__, _meta, [:do]}, body} -> Sourceror.get_range(body)
      {:do, body} -> Sourceror.get_range(body)
      _pair -> nil
    end)
  end

  defp start_line(node) do
    %{start: [line: line, column: _]} = Sourceror.get_range(node)
    line
  end

  defp to_atom(name) when is_atom(name), do: name
  defp to_atom(name) when is_binary(name), do: String.to_atom(name)

  defp parse(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, "not parseable — #{inspect(reason)}"}
    end
  end
end
