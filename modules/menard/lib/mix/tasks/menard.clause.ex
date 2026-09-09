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
    case argv do
      ["replace", file, na, head, code] ->
        write(file, &Clause.replace_body(&1, na, head, code))

      ["delete", file, na, head] ->
        write(file, &Clause.delete(&1, na, head))

      ["insert-after", file, na, head, code] ->
        write(file, &Clause.insert_after(&1, na, head, code))

      ["insert-before", file, na, head, code] ->
        write(file, &Clause.insert_before(&1, na, head, code))

      _ ->
        Mix.raise(
          "usage: mix menard.clause (replace|delete|insert-after|insert-before) FILE name/arity HEAD [CODE]"
        )
    end
  end

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
