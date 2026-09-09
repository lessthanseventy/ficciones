defmodule Menard.Find do
  @moduledoc """
  Search that knows what a call, a def or an alias is — grep for code. Every hit is
  `%{line, column, kind, text}` from the node's own source range; strings and comments never
  match. `calls/2` takes a bare local name or `Mod.fun`, and resolves the file's aliases so an
  aliased call (`Channels.general`) is found by its full name (`Server.Channels.general`).
  """

  alias Sourceror.Zipper

  @def_kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp]

  @type hit :: %{line: pos_integer(), column: pos_integer(), kind: atom(), text: String.t()}

  @doc "Call sites of `target`: `\"fun\"` (local) or `\"Mod.Sub.fun\"` (remote, alias-aware)."
  @spec calls(String.t(), String.t()) :: [hit()]
  def calls(source, target) do
    {mod, fun} = split_target(target)

    # a def head looks exactly like a local call — those positions are excluded
    heads = source |> walk(&def_head/2) |> MapSet.new(&{&1.line, &1.column})

    source
    |> walk(fn node, aliases ->
      case node do
        {^fun, _meta, args} when is_list(args) and is_nil(mod) ->
          {:call, node}

        {{:., _, [{:__aliases__, _, parts}, ^fun]}, _meta, args} when is_list(args) and not is_nil(mod) ->
          if expand(parts, aliases) == mod, do: {:call, node}, else: nil

        _ ->
          nil
      end
    end)
    |> Enum.reject(&MapSet.member?(heads, {&1.line, &1.column}))
  end

  defp def_head({kind, _meta, [head | _]}, _aliases) when kind in @def_kinds, do: {:head, strip_guard(head)}
  defp def_head(_node, _aliases), do: nil

  defp strip_guard({:when, _, [call | _]}), do: call
  defp strip_guard(call), do: call

  @doc "Definitions of `name` or `name/arity`, any def kind."
  @spec defs(String.t(), String.t()) :: [hit()]
  def defs(source, name_arity) do
    {name, arity} = split_name_arity(name_arity)

    walk(source, fn node, _aliases ->
      case node do
        {kind, _meta, [head | _]} when kind in @def_kinds ->
          case def_name_arity(head) do
            {^name, a} when is_nil(arity) or a == arity -> {kind, node, head_only(kind, head)}
            _ -> nil
          end

        _ ->
          nil
      end
    end)
  end

  @doc "Where module `mod` is aliased (`alias A.B` or `alias A.{B, C}`)."
  @spec aliases(String.t(), String.t()) :: [hit()]
  def aliases(source, mod) do
    walk(source, fn node, _aliases ->
      case node do
        {:alias, _meta, [{:__aliases__, _, parts}]} ->
          if Enum.join(parts, ".") == mod, do: {:alias, node}, else: nil

        {:alias, _meta, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, subs}]} ->
          if Enum.any?(subs, fn {:__aliases__, _, p} -> Enum.join(base ++ p, ".") == mod end),
            do: {:alias, node},
            else: nil

        _ ->
          nil
      end
    end)
  end

  # -- walking ---------------------------------------------------------------

  # Walk every node with the aliases seen so far (a flat, file-wide map — good enough for a
  # module's worth of `alias` lines); `match.(node, aliases)` answers `{kind, node_to_report}`.
  defp walk(source, match) do
    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        aliases = collect_aliases(ast)

        ast
        |> Zipper.zip()
        |> Zipper.traverse([], fn z, acc ->
          case match.(Zipper.node(z), aliases) do
            {kind, report} -> {z, [hit(kind, report, nil) | acc]}
            {kind, report, text} -> {z, [hit(kind, report, text) | acc]}
            nil -> {z, acc}
          end
        end)
        |> elem(1)
        |> Enum.reverse()

      {:error, _} ->
        []
    end
  end

  defp hit(kind, node, text) do
    text = text || one_line(node)

    case Sourceror.get_range(node) do
      %{start: [line: l, column: c]} -> %{line: l, column: c, kind: kind, text: text}
      _ -> %{line: 0, column: 0, kind: kind, text: text}
    end
  end

  defp one_line(node), do: node |> Sourceror.to_string() |> String.split("\n") |> List.first()

  # `def name(args)` as text, without the body — the head is what a search shows.
  defp head_only(kind, head), do: "#{kind} " <> Sourceror.to_string(head)

  defp collect_aliases(ast) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse(%{}, fn z, acc ->
      case Zipper.node(z) do
        {:alias, _, [{:__aliases__, _, parts}]} ->
          {z, Map.put(acc, List.last(parts), Enum.join(parts, "."))}

        {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, subs}]} ->
          {z,
           Enum.reduce(subs, acc, fn {:__aliases__, _, p}, a ->
             Map.put(a, List.last(p), Enum.join(base ++ p, "."))
           end)}

        _ ->
          {z, acc}
      end
    end)
    |> elem(1)
  end

  # A module reference's full name: the first segment may be an alias.
  defp expand([first | rest], aliases) do
    case Map.fetch(aliases, first) do
      {:ok, full} -> Enum.join([full | Enum.map(rest, &Atom.to_string/1)], ".")
      :error -> Enum.map_join([first | rest], ".", &Atom.to_string/1)
    end
  end

  defp split_target(target) do
    case String.split(target, ".") do
      [fun] -> {nil, String.to_atom(fun)}
      parts -> {parts |> Enum.drop(-1) |> Enum.join("."), parts |> List.last() |> String.to_atom()}
    end
  end

  defp split_name_arity(spec) do
    case String.split(spec, "/") do
      [name, arity] -> {String.to_atom(name), String.to_integer(arity)}
      [name] -> {String.to_atom(name), nil}
    end
  end

  defp def_name_arity({:when, _, [call | _]}), do: def_name_arity(call)
  defp def_name_arity({name, _, args}) when is_list(args), do: {name, length(args)}
  defp def_name_arity({name, _, _}), do: {name, 0}
end
