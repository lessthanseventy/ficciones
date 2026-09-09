defmodule Mix.Tasks.Menard.Deps do
  @shortdoc "What a function references: mix menard.deps FILE name/arity"
  @moduledoc """
  `mix menard.deps lib/a.ex go/1` — the local calls it makes (and which OTHER functions here share
  them), the remote calls, the modules its body names, and the attributes it reads.

  The read that answers "can this move, and what comes with it?". A local with no sharers can
  travel with the function; one with sharers cannot, and the source module has to keep it.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [module: :string])

    case args do
      [file, name_arity] ->
        case Menard.Deps.of(File.read!(Menard.resolve(file)), name_arity, module: opts[:module]) do
          {:error, message} -> Mix.raise(message)
          report -> Mix.shell().info(render(report))
        end

      _ ->
        Mix.raise("usage: mix menard.deps FILE name/arity [--module Mod]")
    end
  end

  defp render(report) do
    [
      section("locals", Enum.map(report.locals, &local/1)),
      section("remotes", report.remotes),
      section("modules", report.modules),
      section("attributes", Enum.map(report.attributes, &"@#{&1}"))
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp local(%{call: call, shared_with: []}), do: "#{call} (free to move)"
  defp local(%{call: call, shared_with: others}), do: "#{call} (also used by #{Enum.join(others, ", ")})"

  defp section(_title, []), do: ""
  defp section(title, lines), do: "#{title}:\n" <> Enum.map_join(lines, "\n", &("  " <> &1))
end
