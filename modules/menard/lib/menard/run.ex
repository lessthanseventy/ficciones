defmodule Menard.Run do
  @moduledoc """
  The run verbs' parsers: ExUnit's output → the counts and each failure as data (name, module,
  where, the assertion's code/left/right or the error), and a tail that is the summary, not the
  logs a suite prints on its way. `mix menard.run` prints what these return, as one JSON line.
  """

  @doc """
  A run verb in the mix project at `dir` — `"check"` (its `mix precommit`), `"test"` (args: files,
  file:line), `"format"` (args: files; reports what changed), `"compile"` (warnings as
  diagnostics) — as one map with `ok`. Both doors (`mix menard.run`, the MCP `run` tool) call this.
  """
  def result(dir, "check", _args), do: shell(dir, ["precommit"])

  def result(dir, "test", args) do
    {out, status} = mix(dir, ["test" | args])
    out |> parse_test(status) |> with_sources(dir)
  end

  def result(dir, "format", files) do
    files = Enum.map(files, &Path.expand(&1, dir))
    before = Map.new(files, &{&1, File.read!(&1)})
    {out, status} = mix(dir, ["format" | files])
    changed = Enum.filter(files, &(File.read!(&1) != before[&1]))
    %{ok: status == 0, exit: status, changed: changed, tail: tail(out)}
  end

  def result(dir, "compile", _args) do
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

  @doc "Parse `mix test` output (+ its exit status) into `%{ok, exit, tests, failed, failures, tail}`."
  def parse_test(out, status) do
    {tests, failed} = counts(out)

    %{
      ok: status == 0,
      exit: status,
      tests: tests,
      failed: failed,
      failures: failures(out),
      tail: summary(out)
    }
  end

  @doc """
  Attach each failure's `source`: the test's body as written, from `at`'s file (under `root`)
  starting at its line and ending at the matching `end` (the first line at the test's indent).
  """
  def with_sources(%{failures: failures} = result, root) do
    %{result | failures: Enum.map(failures, &Map.put(&1, :source, source_of(&1[:at], root)))}
  end

  defp source_of(nil, _root), do: nil

  defp source_of(at, root) do
    [file, line] = String.split(at, ":")
    path = Path.expand(file, root)

    with true <- File.exists?(path),
         lines <- File.read!(path) |> String.split("\n"),
         {start, _} <- Integer.parse(line),
         [head | rest] <- Enum.drop(lines, start - 1) do
      indent = String.length(head) - String.length(String.trim_leading(head))

      body =
        Enum.take_while(
          rest,
          &(String.trim(&1) != "end" or String.length(&1) - String.length(String.trim_leading(&1)) != indent)
        )

      closer = Enum.at(rest, length(body))
      Enum.join([head | body] ++ List.wrap(closer), "\n")
    else
      _ -> nil
    end
  end

  # ExUnit ≥ 1.20 prints `Result: 5 passed` / `Result: 3/5 passed`; older prints `5 tests, 2 failures`.
  defp counts(out) do
    cond do
      m = Regex.run(~r/Result: (\d+)\/(\d+) passed/, out) ->
        [_, passed, total] = m
        {String.to_integer(total), String.to_integer(total) - String.to_integer(passed)}

      m = Regex.run(~r/Result: (\d+) passed/, out) ->
        [_, passed] = m
        {String.to_integer(passed), 0}

      m = Regex.run(~r/(\d+) tests?, (\d+) failures?/, out) ->
        [_, tests, failed] = m
        {String.to_integer(tests), String.to_integer(failed)}

      true ->
        {nil, nil}
    end
  end

  # Each `N) test NAME (Module)` block up to the next block or the summary.
  defp failures(out) do
    ~r/^\s*\d+\) test (.+?) \((\S+)\)\n(.*?)(?=^\s*\d+\) test |\nFinished in|\z)/ms
    |> Regex.scan(out)
    |> Enum.map(fn [_, name, module, body] ->
      %{
        name: name,
        module: module,
        at: first(~r/^\s*(\S+_test\.exs:\d+)\s*$/m, body),
        code: first(~r/^\s*code:\s+(.+)$/m, body),
        left: first(~r/^\s*left:\s+(.+)$/m, body),
        right: first(~r/^\s*right:\s+(.+)$/m, body),
        error: first(~r/^\s*\*\* (.+)$/m, body)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end)
  end

  defp first(re, text) do
    case Regex.run(re, text) do
      [_, v] -> String.trim(v)
      _ -> nil
    end
  end

  # From ExUnit's `Finished in` line to the end — the summary lines only.
  defp summary(out) do
    case Regex.run(~r/(Finished in .*)\z/s, out) do
      [_, tail] ->
        tail |> String.trim() |> String.split("\n") |> Enum.map_join("\n", &String.trim/1)

      # no run at all: a compile error in a test file — the errors are what matters, not the
      # last five lines (the stack trace under "cannot compile module")
      _ ->
        case Regex.scan(~r/^\s*error: .*(?:\n(?!\s*error:).*)*?\n\s*└─ .*$/m, out) do
          [] ->
            out |> String.split("\n") |> Enum.take(-5) |> Enum.join("\n")

          errors ->
            Enum.map_join(errors, "\n", fn [e] ->
              e |> String.split("\n") |> Enum.map_join("\n", &String.trim/1)
            end)
        end
    end
  end
end
