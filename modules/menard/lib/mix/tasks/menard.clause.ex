defmodule Mix.Tasks.Menard.Clause do
  @shortdoc "Edit one clause: mix menard.clause (replace|delete|insert-after|insert-before) FILE name/arity HEAD [CODE]"
  @moduledoc """
  `mix menard.clause replace lib/a.ex go/1 ':b' '20'` — swap the clause's body.
  `mix menard.clause delete lib/a.ex go/1 ':a'` — remove the clause (and its glued comment).
  `mix menard.clause insert-after lib/a.ex go/1 ':a' 'def go(:c), do: 3'` — add a clause after it.

  HEAD is the clause's args as written, plus its guard (`'x when is_integer(x)'`); whitespace is
  ignored. CODE may span lines (a block body). Only the clause's bytes change
  (`Menard.Clause`); the file is formatted after. A miss lists the clauses that exist.
  """
  use Mix.Task

  alias Menard.Clause

  @impl true
  def run(argv) do
    {flags, argv, _} = OptionParser.parse(argv, strict: [nth: :integer])

    case normalize(argv) do
      ["replace", file, na, head, code] ->
        write(file, &Clause.replace_body(&1, na, head, code, flags))

      ["rewrite", file, na, head, code] ->
        write(file, &Clause.rewrite(&1, na, head, code, flags))

      ["delete", file, na, head] ->
        write(file, &Clause.delete(&1, na, head, flags))

      ["insert_after", file, na, head, code] ->
        write(file, &Clause.insert_after(&1, na, head, code, flags))

      ["insert_before", file, na, head, code] ->
        write(file, &Clause.insert_before(&1, na, head, code, flags))

      # placement follows the code (a defp with the defps, a def with the defs) unless named
      ["insert_at", file, module, code] ->
        write(file, &Clause.insert_at(&1, module(module), nil, code))

      ["insert_at", file, module, where, code] when where in ["top", "bottom"] ->
        write(file, &Clause.insert_at(&1, module(module), where, code))

      ["doc", file, na, head, text] ->
        write(file, &Clause.doc(&1, na, head, text, flags))

      ["doc", file, na, head] ->
        write(file, &Clause.doc(&1, na, head, nil, flags))

      # every clause at once — a half-flipped function does not compile
      ["visibility", file, na, want] ->
        write(file, &Clause.visibility(&1, na, visibility(want)))

      _ ->
        Mix.raise(
          "usage: mix menard.clause (replace|rewrite|delete|insert-after|insert-before) FILE name/arity HEAD [CODE] [--nth N]\n" <>
            "       mix menard.clause insert-at FILE (Mod.Name|-) [top|bottom] CODE\n" <>
            "       mix menard.clause doc FILE name/arity HEAD [TEXT]   (no TEXT deletes it)\n" <>
            "       mix menard.clause visibility FILE name/arity (public|private)"
        )
    end
  end

  # The two doors spelled these differently — the CLI with dashes, the MCP with underscores — so a
  # verb learned at one door failed at the other. Both spellings work everywhere now.
  defp normalize([verb | rest]) when is_binary(verb), do: [String.replace(verb, "-", "_") | rest]
  defp normalize(argv), do: argv

  # `-` (or an empty string) means "the file's one module" — there is nothing to name.
  defp module(m) when m in ["-", ""], do: nil
  defp module(m), do: m

  defp visibility("public"), do: :public
  defp visibility("private"), do: :private
  defp visibility(other), do: Mix.raise("visibility must be public or private, got #{other}")

  defp write(file, edit) do
    file = Menard.resolve(file)

    case edit.(File.read!(file)) do
      {:error, message} ->
        Mix.raise(message)

      out ->
        case Menard.checked_write(file, out) do
          :ok -> :ok
          {:error, message} -> Mix.raise(message)
        end
    end

    Mix.shell().info("menard.clause: #{file} written")
  end
end
