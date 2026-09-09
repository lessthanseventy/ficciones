defmodule Menard.Deps do
  @moduledoc """
  What one function actually references — the read that answers "can this move, and what comes
  with it?".

  There is deliberately no `move` verb. Moving a function is not a patch: its body resolves
  against the SOURCE module's aliases, it may call private helpers that other functions also need,
  it may read module attributes that do not travel, and every call site has to change. Get any one
  wrong and you get a green edit and a red compile. So Menard reports, and the move is a recipe
  out of verbs that already exist:

      deps → clause insert-at (into the destination) → directive add (the aliases it needs)
           → clause delete (from the source) → find calls (fix the call sites) → run compile

  `of/3` returns `%{locals, remotes, modules, attributes}`. `locals` is the part that decides the
  question: each is a function of THIS module that the queried one calls, with `shared_with` —
  every other function here that also calls it. A local with an empty `shared_with` can travel; one
  with entries cannot, and the source module has to keep (and probably publicise) it.
  """

  alias Menard.Clause
  alias Sourceror.Zipper

  @kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp]

  @type report :: %{
          locals: [%{call: String.t(), shared_with: [String.t()]}],
          remotes: [String.t()],
          modules: [String.t()],
          attributes: [atom()]
        }

  @doc "What `name/arity` references. `module` names which module in a file that has several."
  @spec of(String.t(), String.t(), keyword()) :: report() | {:error, String.t()}
  def of(source, name_arity, opts \\ []) do
    with {:ok, want} <- split(name_arity),
         {:ok, ast} <- parse(source),
         {:ok, module} <- Clause.module_scope(ast, opts[:module]) do
      defs = definitions(module)

      case Enum.filter(defs, &(key(&1) == want)) do
        [] ->
          {:error,
           "no #{name(want)} in this module — have: #{Enum.map_join(Enum.uniq(Enum.map(defs, &name(key(&1)))), ", ", & &1)}"}

        mine ->
          report(mine, defs, want)
      end
    end
  end

  defp report(mine, defs, want) do
    refs = Enum.reduce(mine, empty(), fn {_key, node}, acc -> collect(node, acc) end)
    own = MapSet.new(defs, &key/1)

    locals =
      refs.calls
      |> Enum.filter(&MapSet.member?(own, &1))
      |> Enum.reject(&(&1 == want))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn call -> %{call: name(call), shared_with: shared_with(defs, call, want)} end)

    %{
      locals: locals,
      remotes: refs.remotes |> Enum.uniq() |> Enum.sort(),
      modules: refs.modules |> Enum.uniq() |> Enum.sort(),
      attributes: refs.attributes |> Enum.uniq() |> Enum.sort()
    }
  end

  # Which OTHER functions of this module call `target` — the reason a helper cannot simply travel
  # with the function being moved.
  defp shared_with(defs, target, want) do
    defs
    |> Enum.reject(&(key(&1) == want))
    |> Enum.filter(fn {_key, node} -> target in collect(node, empty()).calls end)
    |> Enum.map(&name(key(&1)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # -- walking a body -------------------------------------------------------

  # The BODY only. Walking the whole def node counts its own head as a call, so every function came
  # back "shared with" itself and nothing ever looked free to move.
  defp collect({_kind, _meta, args}, acc) when is_list(args) and args != [] do
    args
    |> List.last()
    |> Zipper.zip()
    |> Zipper.traverse(acc, fn zipper, found -> {zipper, absorb(Zipper.node(zipper), found)} end)
    |> elem(1)
  end

  defp collect(_node, acc), do: acc

  # A remote call: `Mod.fun(args)`. Its module counts as a reference too — that is the alias that
  # has to travel with the code.
  defp absorb({{:., _dot, [{:__aliases__, _am, parts}, fun]}, _meta, args}, acc)
       when is_atom(fun) and is_list(args) do
    %{
      acc
      | remotes: [Enum.join(parts, ".") <> "." <> "#{fun}/#{length(args)}" | acc.remotes],
        modules: [Enum.join(parts, ".") | acc.modules]
    }
  end

  # A bare module mention (`alias`-resolved, a struct, a behaviour).
  defp absorb({:__aliases__, _meta, parts}, acc), do: %{acc | modules: [Enum.join(parts, ".") | acc.modules]}

  # An attribute READ (`@kinds`), which is what does NOT travel with a moved function.
  defp absorb({:@, _meta, [{name, _inner, args}]}, acc) when is_atom(name) and not is_list(args),
    do: %{acc | attributes: [name | acc.attributes]}

  # A local call. Every one is collected here and intersected with the module's own definitions
  # later, which is what keeps `if`, `case`, `|>` and the rest of Kernel out of the answer.
  defp absorb({fun, _meta, args}, acc) when is_atom(fun) and is_list(args),
    do: %{acc | calls: [{fun, length(args)} | acc.calls]}

  defp absorb(_node, acc), do: acc

  defp empty, do: %{calls: [], remotes: [], modules: [], attributes: []}

  # -- shapes ---------------------------------------------------------------

  defp definitions(module) do
    module
    |> Clause.module_body()
    |> Enum.flat_map(fn
      {kind, _meta, [head | _rest]} = node when kind in @kinds -> [{head_key(head), node}]
      _other -> []
    end)
  end

  defp head_key({:when, _meta, [call | _guard]}), do: head_key(call)
  defp head_key({fun, _meta, args}) when is_list(args), do: {fun, length(args)}
  defp head_key({fun, _meta, _nil_args}), do: {fun, 0}

  defp key({key, _node}), do: key
  defp name({fun, arity}), do: "#{fun}/#{arity}"

  defp split(name_arity) do
    with [fun, arity] <- String.split(name_arity, "/"),
         {arity, ""} <- Integer.parse(arity) do
      {:ok, {String.to_atom(fun), arity}}
    else
      _ -> {:error, "expected name/arity, got #{inspect(name_arity)}"}
    end
  end

  defp parse(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, "not parseable — #{inspect(reason)}"}
    end
  end
end
