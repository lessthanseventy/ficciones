defmodule Menard.Attr do
  @moduledoc """
  Module attributes — `@hints`, `@colors`, `@panes`, `@kinds`. The tables a module keeps at the
  top, which every clause verb walks straight past because an attribute is not a clause.

  This was the most-hit gap in Menard's first week of real use: editing `@hints` in a status bar,
  a `@type`, a `@colors` map, all fell back to text patching precisely because there was no verb.

  Addressed by NAME. A name several attributes share is refused with their lines rather than
  guessed at — `@doc`, `@impl` and `@spec` repeat per clause by design, and those belong to the
  clause verbs (`Menard.Clause.delete/4` takes them with the clause; `visibility/3` drops a `@doc`
  when it privatises).
  """

  alias Menard.Clause

  @doc "The attribute's value exactly as written, or `{:error, …}` if it is missing or ambiguous."
  @spec get(String.t(), String.t() | atom(), keyword()) :: String.t() | {:error, String.t()}
  def get(source, name, opts \\ []) do
    with {:ok, node} <- one(source, name, opts), do: value_text(node)
  end

  @doc """
  Set `@name` to `value` (the value as you would write it). Replaces the existing attribute's
  value, or adds the attribute when it isn't there yet — at the TOP of the module's tables, above
  the first attribute or definition, since an attribute another attribute reads must precede it.
  """
  @spec set(String.t(), String.t() | atom(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def set(source, name, value, opts \\ []) do
    case one(source, name, opts) do
      {:ok, node} -> replace(source, node, name, value)
      {:error, :missing} -> add(source, name, value, opts)
      {:error, message} -> {:error, message}
    end
  end

  @doc "Remove the attribute and the lines it occupies."
  @spec delete(String.t(), String.t() | atom(), keyword()) :: String.t() | {:error, String.t()}
  def delete(source, name, opts \\ []) do
    with {:ok, node} <- one(source, name, opts) do
      %{start: [line: a, column: _], end: [line: b, column: _]} = Sourceror.get_range(node)
      drop_lines(source, a, b)
    end
  end

  @doc "Every attribute the module sets, as `{name, line}` in source order — the read half."
  @spec list(String.t(), keyword()) :: [{atom(), pos_integer()}] | {:error, String.t()}
  def list(source, opts \\ []) do
    with {:ok, body} <- body(source, opts) do
      body
      |> Enum.flat_map(fn node ->
        case attr_name(node) do
          nil -> []
          name -> [{name, start_line(node)}]
        end
      end)
    end
  end

  # -- locating ------------------------------------------------------------

  defp one(source, name, opts) do
    want = to_atom(name)

    with {:ok, body} <- body(source, opts) do
      case Enum.filter(body, &(attr_name(&1) == want)) do
        [node] ->
          {:ok, node}

        [] ->
          {:error, :missing}

        many ->
          lines = Enum.map_join(many, ", ", &to_string(start_line(&1)))

          {:error,
           "@#{want} is set #{length(many)} times (lines #{lines}) — attributes that repeat per clause belong to the clause verbs"}
      end
    end
  end

  defp body(source, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, node} <- Clause.module_scope(ast, opts[:module]) do
      {:ok, Clause.module_body(node)}
    end
  end

  # -- editing -------------------------------------------------------------

  defp replace(source, node, name, value) do
    %{start: [line: a, column: col], end: [line: b, column: _]} = Sourceror.get_range(node)
    indent = String.duplicate(" ", col - 1)
    written = indent <> "@#{to_atom(name)} " <> reindent(value, indent)

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

  # A module's tables live above its functions, so a new attribute goes before the first ATTRIBUTE
  # OR definition — whichever comes first. Not merely before the first definition: an attribute that
  # another attribute uses has to precede it, and Elixir only warns when it does not.
  defp add(source, name, value, opts) do
    with {:ok, ast} <- parse(source),
         {:ok, module} <- Clause.module_scope(ast, opts[:module]) do
      body = Clause.module_body(module)

      # BEFORE the first attribute-set OR definition, not merely before the first definition: an
      # attribute that another attribute uses (`@colors %{a: @body}`) has to precede it, and a module
      # whose attributes sit above its defs would otherwise take the new one BELOW its own consumer,
      # where Elixir reads it as nil and only warns. First is the one position that is always safe.
      case Enum.find(body, &(definition?(&1) or attr_name(&1) != nil)) do
        nil -> {:error, "nothing to place @#{to_atom(name)} above — the module has no definitions"}
        first -> insert_before(source, first, name, value)
      end
    end
  end

  defp insert_before(source, node, name, value) do
    %{start: [line: line, column: col]} = Sourceror.get_range(node)
    indent = String.duplicate(" ", col - 1)
    written = indent <> "@#{to_atom(name)} " <> reindent(value, indent) <> "\n\n"
    at = %{start: [line: line, column: 1], end: [line: line, column: 1]}
    Sourceror.patch_string(source, [%{range: at, change: written, preserve_indentation: false}])
  end

  defp drop_lines(source, a, b) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {_text, line} -> line >= a and line <= b end)
    |> Enum.map_join("\n", &elem(&1, 0))
  end

  # -- shapes --------------------------------------------------------------

  # `@name value`. An attribute READ (`@name` with no argument) is not a set and never matches.
  defp attr_name({:@, _meta, [{name, _inner, args}]}) when is_atom(name) and is_list(args) and args != [],
    do: name

  defp attr_name(_node), do: nil

  defp value_text({:@, _meta, [{_name, _inner, [value]}]}), do: Sourceror.to_string(value)
  defp value_text(_node), do: {:error, "not an attribute with a value"}

  defp definition?({kind, _meta, _args})
       when kind in [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp],
       do: true

  defp definition?(_node), do: false

  defp start_line(node) do
    %{start: [line: line, column: _]} = Sourceror.get_range(node)
    line
  end

  # A written value keeps its own shape; every line after the first is shifted to the attribute's
  # column, so a multi-line list or map lands as a block rather than a ragged one.
  defp reindent(value, indent) do
    case value |> String.trim() |> String.split("\n") do
      [one] -> one
      [first | rest] -> Enum.join([first | Enum.map(rest, &(indent <> &1))], "\n")
    end
  end

  defp to_atom(name) when is_atom(name), do: name
  defp to_atom(name) when is_binary(name), do: String.to_atom(String.trim_leading(name, "@"))

  defp parse(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, "not parseable — #{inspect(reason)}"}
    end
  end
end
