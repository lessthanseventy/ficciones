defmodule Mix.Tasks.Menard.Inspect do
  @shortdoc "Introspect a project: mix menard.inspect [--in DIR] (callers MOD[.fun/arity]|exports [FILE]|deps) [--json]"
  @moduledoc """
  The read-only verbs that look across a project's files (single-engine, Mix):

      mix menard.inspect --in modules/server callers Server.Worktree     # files calling into it (mix xref)
      mix menard.inspect --in modules/server callers Server.Worktree.ensure/2
      mix menard.inspect --in modules/server exports [lib/server.ex]     # the :boundary export list
      mix menard.inspect --in modules/server deps                        # outdated packages + advisories

  `--json` prints data; otherwise one line per row.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [json: :boolean, in: :string])
    dir = Menard.resolve(opts[:in] || ".")
    json? = opts[:json] == true

    case args do
      ["callers", target] ->
        emit(json?, %{target: target, callers: callers(dir, target)}, & &1.callers)

      ["exports"] ->
        emit(json?, %{exports: exports(boundary_file(dir))}, & &1.exports)

      ["exports", file] ->
        emit(json?, %{exports: exports(Path.expand(file, dir))}, & &1.exports)

      ["deps"] ->
        emit(json?, deps(dir), &(&1.outdated ++ &1.advisories))

      _ ->
        Mix.raise(
          "usage: mix menard.inspect [--in DIR] (callers MOD[.fun/arity]|exports [FILE]|deps) [--json]"
        )
    end
  end

  defp callers(dir, target) do
    {out, _} = mix(dir, ["xref", "callers", target])
    out |> String.split("\n") |> Enum.filter(&String.contains?(&1, "(")) |> Enum.map(&String.trim/1)
  end

  # The project's boundary file: the first lib/*.ex that `use Boundary` with an exports list.
  defp boundary_file(dir) do
    dir
    |> Path.join("lib/*.ex")
    |> Path.wildcard()
    |> Enum.find(fn f -> f |> File.read!() |> String.contains?("use Boundary") end) ||
      Mix.raise("no lib/*.ex with `use Boundary` under #{dir}")
  end

  # The boundary's export list, as module names — what the project promises a consumer.
  defp exports(file) do
    {:ok, ast} = Sourceror.parse_string(File.read!(file))

    ast
    |> Sourceror.Zipper.zip()
    |> Sourceror.Zipper.traverse([], fn z, acc ->
      case Sourceror.Zipper.node(z) do
        {:use, _, [{:__aliases__, _, [:Boundary]}, opts]} -> {z, acc ++ export_names(opts)}
        _ -> {z, acc}
      end
    end)
    |> elem(1)
  end

  defp export_names(opts) do
    case Enum.find(opts, fn {{:__block__, _, [k]}, _} -> k == :exports end) do
      {_, {:__block__, _, [list]}} when is_list(list) ->
        Enum.map(list, &(&1 |> Sourceror.to_string() |> String.split("\n") |> List.last()))

      _ ->
        []
    end
  end

  defp deps(dir) do
    {outdated, _} = mix(dir, ["hex.outdated"])
    {audit, _} = mix(dir, ["hex.audit"])

    %{
      outdated: outdated |> String.split("\n") |> Enum.filter(&Regex.match?(~r/^\S+\s+\d/, &1)),
      advisories: audit |> String.split("\n") |> Enum.filter(&String.contains?(&1, "vulnerab"))
    }
  end

  defp mix(dir, args), do: System.cmd("mix", args, cd: dir, stderr_to_stdout: true, env: [{"MIX_ENV", "dev"}])

  defp emit(true, data, _lines), do: Mix.shell().info(JSON.encode!(data))
  defp emit(false, data, lines), do: data |> lines.() |> Enum.each(fn line -> Mix.shell().info(line) end)
end
