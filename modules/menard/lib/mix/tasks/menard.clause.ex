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
    case normalize(argv) do
      ["replace", file, na, head, code] ->
        write(file, &Clause.replace_body(&1, na, head, code))

      ["rewrite", file, na, head, code] ->
        write(file, &Clause.rewrite(&1, na, head, code))

      ["delete", file, na, head] ->
        write(file, &Clause.delete(&1, na, head))

      ["insert_after", file, na, head, code] ->
        write(file, &Clause.insert_after(&1, na, head, code))

      ["insert_before", file, na, head, code] ->
        write(file, &Clause.insert_before(&1, na, head, code))

      # placement follows the code (a defp with the defps, a def with the defs) unless named
      ["insert_at", file, module, code] ->
        write(file, &Clause.insert_at(&1, module(module), nil, code))

      ["insert_at", file, module, where, code] when where in ["top", "bottom"] ->
        write(file, &Clause.insert_at(&1, module(module), where, code))

      _ ->
        Mix.raise(
          "usage: mix menard.clause (replace|rewrite|delete|insert-after|insert-before) FILE name/arity HEAD [CODE]\n" <>
            "       mix menard.clause insert-at FILE (Mod.Name|-) [top|bottom] CODE"
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

  defp write(file, edit) do
    file = Menard.resolve(file)

    case edit.(File.read!(file)) do
      {:error, message} -> Mix.raise(message)
      out -> File.write!(file, out)
    end

    Menard.format(file)
    Mix.shell().info("menard.clause: #{file} written")
  end
end
