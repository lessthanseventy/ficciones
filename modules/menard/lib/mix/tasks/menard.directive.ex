defmodule Mix.Tasks.Menard.Directive do
  @shortdoc "alias/import/require/use, placed where they belong: mix menard.directive add|remove|list FILE ..."
  @moduledoc """
  `mix menard.directive add lib/a.ex alias Console.Picker` — add it in sorted position.
  `mix menard.directive add lib/a.ex import Console.Panel 'only: [pad: 3]'` — with its options.
  `mix menard.directive remove lib/a.ex alias Console.Picker` — take it out.
  `mix menard.directive list lib/a.ex` — what the module already pulls in.

  The placement is the point: Elixir's conventional order is `use`, `import`, `alias`, `require`,
  each alphabetised, and a formatter plugin that sorts them will move a directive dropped at a
  guessed line. `--module Mod.Name` names which module in a file that has several.
  """
  use Mix.Task

  alias Menard.Directive

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [module: :string])

    case args do
      ["list", file] ->
        file = Menard.resolve(file)

        case Directive.list(File.read!(file), module: opts[:module]) do
          {:error, message} -> Mix.raise(message)
          found -> Mix.shell().info(Enum.map_join(found, "\n", fn {kind, target} -> "#{kind} #{target}" end))
        end

      ["add", file, kind, target | rest] ->
        edit(file, &Directive.add(&1, atom(kind), target, module: opts[:module], args: List.first(rest)))

      ["remove", file, kind, target] ->
        edit(file, &Directive.remove(&1, atom(kind), target, module: opts[:module]))

      _ ->
        Mix.raise(
          "usage: mix menard.directive add FILE (alias|import|require|use) MOD [OPTS] [--module Mod]\n" <>
            "       mix menard.directive remove FILE (alias|import|require|use) MOD [--module Mod]\n" <>
            "       mix menard.directive list FILE [--module Mod]"
        )
    end
  end

  defp atom(kind) when kind in ~w(alias import require use), do: String.to_existing_atom(kind)
  defp atom(kind), do: Mix.raise("unknown directive #{kind} — one of alias, import, require, use")

  defp edit(file, change) do
    file = Menard.resolve(file)

    case change.(File.read!(file)) do
      {:error, message} ->
        Mix.raise(message)

      out ->
        case Menard.checked_write(file, out) do
          :ok -> :ok
          {:error, message} -> Mix.raise(message)
        end
    end

    Mix.shell().info("menard.directive: #{file} written")
  end
end
