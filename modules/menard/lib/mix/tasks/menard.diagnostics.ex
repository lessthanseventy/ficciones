defmodule Mix.Tasks.Menard.Diagnostics do
  @shortdoc "Compiler diagnostics as data: mix menard.diagnostics [--in DIR] [--json]"
  @moduledoc """
  `mix menard.diagnostics [--in DIR] [--json]` — the target project's forced compile, its
  warnings as data: one line per diagnostic (`file:line severity message`), or `--json`. Exit
  status 1 when anything is reported, so a caller can gate on it.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [json: :boolean, in: :string])
    dir = Menard.resolve(opts[:in] || ".")

    {out, _} =
      System.cmd("mix", ["compile", "--force"], cd: dir, stderr_to_stdout: true, env: [{"MIX_ENV", "dev"}])

    rows =
      ~r/(warning|error): (.+)\n(?:.*\n)*?\s*└─ ([^\s:]+):(\d+)/
      |> Regex.scan(out)
      |> Enum.map(fn [_, sev, msg, file, line] ->
        %{severity: sev, message: msg, file: file, line: String.to_integer(line)}
      end)

    if opts[:json] == true,
      do: Mix.shell().info(JSON.encode!(rows)),
      else: Enum.each(rows, &Mix.shell().info("#{&1.file}:#{&1.line} #{&1.severity} #{&1.message}"))

    if rows != [], do: exit({:shutdown, 1})
  end
end
