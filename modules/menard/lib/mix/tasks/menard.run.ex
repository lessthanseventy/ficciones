defmodule Mix.Tasks.Menard.Run do
  @shortdoc "A run verb with structured output: mix menard.run (check|test|format|compile) [ARGS]"
  @moduledoc """
  The run-and-update verbs an agent calls instead of a shell chain with greps on the end:

      mix menard.run check                # this app's gate (mix precommit): {ok, exit, tail}
      mix menard.run test [FILE[:LINE]]   # one file / one test, or the suite: {ok, tests, failed, failures: [{name, module, at, code, left, right | error, source}], tail}
      mix menard.run format [FILES]       # format; reports the files it changed
      mix menard.run compile              # compile --warnings-as-errors: {ok, diagnostics}

  Always prints ONE JSON object on the last line, and exits 1 when `ok` is false, so a caller
  reads one line and gates on the status. Human output above it is the underlying task's.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [in: :string])
    dir = Menard.resolve(opts[:in] || ".")

    case args do
      ["check"] -> finish(shell(dir, ["precommit"]))
      ["test" | rest] -> finish(test(dir, rest))
      ["format" | files] -> finish(format(dir, files))
      ["compile"] -> finish(compile(dir))
      _ -> Mix.raise("usage: mix menard.run [--in DIR] (check|test [FILE[:LINE]]|format [FILES]|compile)")
    end
  end

  defp test(dir, args) do
    {out, status} = mix(dir, ["test" | args])
    out |> Menard.Run.parse_test(status) |> Menard.Run.with_sources(dir)
  end

  defp format(dir, files) do
    files = Enum.map(files, &Path.expand(&1, dir))
    before = Map.new(files, &{&1, File.read!(&1)})
    {out, status} = mix(dir, ["format" | files])
    changed = Enum.filter(files, &(File.read!(&1) != before[&1]))
    %{ok: status == 0, exit: status, changed: changed, tail: tail(out)}
  end

  defp compile(dir) do
    {out, status} = mix(dir, ["compile", "--force", "--warnings-as-errors"])

    diagnostics =
      ~r/(warning|error): (.+)\n(?:.*\n)*?\s*└─ ([^\s:]+):(\d+)/
      |> Regex.scan(out)
      |> Enum.map(fn [_, sev, msg, file, line] ->
        %{severity: sev, message: msg, file: file, line: String.to_integer(line)}
      end)

    %{ok: status == 0, exit: status, diagnostics: diagnostics, tail: tail(out)}
  end

  defp shell(dir, args) do
    {out, status} = mix(dir, args)
    %{ok: status == 0, exit: status, tail: tail(out)}
  end

  # the TARGET project's mix, in its own directory and env — never this project's
  defp mix(dir, args), do: System.cmd("mix", args, cd: dir, stderr_to_stdout: true, env: [{"MIX_ENV", "dev"}])

  defp tail(out), do: out |> String.split("\n") |> Enum.take(-12) |> Enum.join("\n")

  defp finish(%{ok: ok} = result) do
    Mix.shell().info(JSON.encode!(result))
    if not ok, do: exit({:shutdown, 1})
  end
end
