defmodule Mix.Tasks.Menard.Stmt do
  @shortdoc "One statement inside a clause body — insert, replace, delete, list"
  @moduledoc """
  ONE statement inside a clause body, addressed the way a clause is: name the clause
  (`name/arity` + HEAD), then the statement by what is WRITTEN.

      mix menard.stmt insert-after FILE init/1 '_opts' 'Bus.subscribe_habits()' 'Import.run()'
      mix menard.stmt replace FILE init/1 '_opts' '0 -> {:ok, :up}' '0 -> {:ok, :running}'
      mix menard.stmt delete FILE init/1 '_opts' 'legacy_call()'
      mix menard.stmt list FILE init/1 '_opts'

  Reaches a line in a body, a step in a `with`, and a `case` arm alike. A miss lists what is
  there; an ambiguous match is refused with line numbers and `--nth`.
  """
  use Mix.Task

  alias Menard.Stmt

  @impl true
  def run(argv) do
    {flags, argv, _} = OptionParser.parse(argv, strict: [nth: :integer])

    case normalize(argv) do
      ["insert_after", file, na, head, match, code] ->
        write(file, &Stmt.insert_after(&1, na, head, match, code, flags))

      ["insert_before", file, na, head, match, code] ->
        write(file, &Stmt.insert_before(&1, na, head, match, code, flags))

      ["replace", file, na, head, match, code] ->
        write(file, &Stmt.replace(&1, na, head, match, code, flags))

      ["delete", file, na, head, match] ->
        write(file, &Stmt.delete(&1, na, head, match, flags))

      ["list", file, na, head] ->
        case Stmt.list(File.read!(Menard.resolve(file)), na, head, flags) do
          {:error, message} -> Mix.raise(message)
          statements -> Mix.shell().info(Enum.map_join(statements, "\n", &"- #{&1}"))
        end

      _ ->
        Mix.raise(
          "usage: mix menard.stmt (insert-after|insert-before|replace) FILE name/arity HEAD MATCH CODE [--nth N]\n" <>
            "       mix menard.stmt delete FILE name/arity HEAD MATCH [--nth N]\n" <>
            "       mix menard.stmt list FILE name/arity HEAD"
        )
    end
  end

  defp normalize([verb | rest]) when is_binary(verb), do: [String.replace(verb, "-", "_") | rest]
  defp normalize(argv), do: argv

  defp write(file, edit) do
    file = Menard.resolve(file)

    case edit.(File.read!(file)) do
      {:error, message} ->
        Mix.raise(message)

      out ->
        case Menard.checked_write(file, out) do
          :ok -> Mix.shell().info("menard.stmt: #{file} written")
          {:error, message} -> Mix.raise(message)
        end
    end
  end
end
