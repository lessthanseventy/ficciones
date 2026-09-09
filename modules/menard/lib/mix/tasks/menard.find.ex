defmodule Mix.Tasks.Menard.Find do
  @shortdoc "Search that knows the code: mix menard.find (calls TARGET|defs NAME[/ARITY]|aliases MOD) [--json] FILE..."
  @moduledoc """
  grep for code (`Menard.Find`): strings and comments never match, and a call is a call.

      mix menard.find calls Server.Channels.general lib/**/*.ex   # remote, alias-aware
      mix menard.find calls general lib/server/channels.ex        # local
      mix menard.find defs general/1 lib/**/*.ex
      mix menard.find aliases Server.Channels lib/**/*.ex

  One line per hit (`file:line:column kind text`), or `--json`. Globs are expanded here.
  """
  use Mix.Task

  alias Menard.Find

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [json: :boolean])

    {finder, files} =
      case args do
        ["calls", target | files] -> {&Find.calls(&1, target), files}
        ["defs", name | files] -> {&Find.defs(&1, name), files}
        ["aliases", mod | files] -> {&Find.aliases(&1, mod), files}
        _ -> Mix.raise("usage: mix menard.find (calls TARGET|defs NAME[/ARITY]|aliases MOD) [--json] FILE...")
      end

    hits =
      files
      |> Enum.flat_map(&(&1 |> Menard.resolve() |> Path.wildcard()))
      |> Enum.flat_map(fn file ->
        file |> File.read!() |> finder.() |> Enum.map(&Map.put(&1, :file, file))
      end)

    if opts[:json] == true,
      do: Mix.shell().info(JSON.encode!(hits)),
      else: Enum.each(hits, &Mix.shell().info("#{&1.file}:#{&1.line}:#{&1.column} #{&1.kind} #{&1.text}"))
  end
end
