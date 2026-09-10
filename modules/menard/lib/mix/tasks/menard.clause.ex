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
    {flags, argv, _} =
      OptionParser.parse(argv, strict: [nth: :integer, to: :string, as: :string, module: :string])

    case normalize(argv) do
      ["replace", file, na, head, code] ->
        write(file, &Clause.replace_body(&1, na, head, code, nth: flags[:nth]))

      ["rewrite", file, na, head, code] ->
        write(file, &Clause.rewrite(&1, na, head, code, nth: flags[:nth]))

      ["delete", file, na, head] ->
        write(file, &Clause.delete(&1, na, head, nth: flags[:nth]))

      ["insert_after", file, na, head, code] ->
        write(file, &Clause.insert_after(&1, na, head, code, nth: flags[:nth]))

      ["insert_before", file, na, head, code] ->
        write(file, &Clause.insert_before(&1, na, head, code, nth: flags[:nth]))

      ["insert_at", file, module, code] ->
        write(file, &Clause.insert_at(&1, module(module), nil, code))

      ["insert_at", file, module, where, code] when where in ["top", "bottom"] ->
        write(file, &Clause.insert_at(&1, module(module), where, code))

      ["move", file, na] ->
        move(file, flags[:to], na, flags[:as], flags[:module])

      ["comment", file, na, head, text] ->
        write(file, &Clause.comment(&1, na, head, text, nth: flags[:nth]))

      ["comment", file, na, head] ->
        write(file, &Clause.comment(&1, na, head, nil, nth: flags[:nth]))

      ["doc", file, na, head, text] ->
        write(file, &Clause.doc(&1, na, head, text, nth: flags[:nth]))

      ["doc", file, na, head] ->
        write(file, &Clause.doc(&1, na, head, nil, nth: flags[:nth]))

      ["visibility", file, na, want] ->
        write(file, &Clause.visibility(&1, na, visibility(want)))

      _ ->
        Mix.raise(
          "usage: mix menard.clause (replace|rewrite|delete|insert-after|insert-before) FILE name/arity HEAD [CODE] [--nth N]\n" <>
            "       mix menard.clause insert-at FILE (Mod.Name|-) [top|bottom] CODE\n" <>
            "       mix menard.clause move FILE name/arity --to DEST [--as Mod.Name]\n" <>
            "       mix menard.clause doc FILE name/arity HEAD [TEXT]       (no TEXT deletes it)\n" <>
            "       mix menard.clause comment FILE name/arity HEAD [TEXT]   (no TEXT deletes it)\n" <>
            "       mix menard.clause visibility FILE name/arity (public|private)"
        )
    end
  end

  # Two files change at once, so neither is written until BOTH edits succeed — a move that half
  # lands is worse than one that does not.
  defp move(file, dest, na, as, module) do
    file = Menard.resolve(file)
    dest = Menard.resolve(dest)

    dest_source =
      cond do
        File.exists?(dest) ->
          File.read!(dest)

        as not in [nil, ""] ->
          "defmodule #{as} do\nend\n"

        true ->
          case derive_module(dest) do
            {:ok, mod} ->
              Mix.shell().info("menard.clause: creating #{dest} as defmodule #{mod}")
              "defmodule #{mod} do\nend\n"

            :error ->
              Mix.raise("#{dest} does not exist and is not inside a mix project — name it with --as Mod.Name")
          end
      end

    case Clause.move(File.read!(file), dest_source, na, module: module) do
      {:error, message} ->
        Mix.raise(message)

      {:ok, out_source, out_dest} ->
        with :ok <- Menard.checked_write(dest, out_dest),
             :ok <- Menard.checked_write(file, out_source) do
          Mix.shell().info("menard.clause: #{na} moved to #{dest}")

          Mix.shell().info(
            "run `mix menard.deps #{file} #{na}` before this to see the aliases and callers it leaves behind"
          )
        else
          {:error, message} -> Mix.raise(message)
        end
    end
  end

  # What a generator would have called it: `lib/my_app/foo/bar.ex` is `MyApp.Foo.Bar`, relative to
  # the nearest mix.exs, with `lib/` or `test/` dropped. Named out loud when it fires, because a
  # derived name is a guess about intent even when the path is unambiguous — `--as` overrides.
  defp derive_module(path) do
    with {:ok, root} <- project_root(Path.dirname(path)) do
      path
      |> Path.relative_to(root)
      |> String.replace(~r{^(lib|test)/}, "")
      |> String.replace(~r{\.exs?$}, "")
      |> Path.split()
      |> Enum.map_join(".", &Macro.camelize/1)
      |> then(&{:ok, &1})
    end
  end

  defp project_root("/"), do: :error
  defp project_root("."), do: :error

  defp project_root(dir) do
    if File.exists?(Path.join(dir, "mix.exs")),
      do: {:ok, dir},
      else: dir |> Path.dirname() |> project_root()
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
