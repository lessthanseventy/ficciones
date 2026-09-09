defmodule Mix.Tasks.Menard.Module do
  @shortdoc "Whole modules in a file: mix menard.module add|list FILE [CODE]"
  @moduledoc """
  `mix menard.module add lib/tools.ex 'defmodule A.B do\\n  def go, do: 1\\nend'` — add a module to a
  file that already has one (`-` for CODE reads stdin). `mix menard.module list FILE`.

  `clause insert-at` puts a function INTO a module and `write` replaces a whole file; neither adds
  a second `defmodule` to a file that already has one — the shape the MCP tool components use.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    case argv do
      ["list", file] ->
        case Menard.Module.list(File.read!(Menard.resolve(file))) do
          {:error, message} -> Mix.raise(message)
          names -> Mix.shell().info(Enum.join(names, "\n"))
        end

      ["add", file, code] ->
        file = Menard.resolve(file)
        code = if code == "-", do: IO.read(:stdio, :eof), else: code

        case Menard.Module.add(File.read!(file), to_string(code)) do
          {:error, message} -> Mix.raise(message)
          out -> File.write!(file, out)
        end

        Menard.format(file)
        Mix.shell().info("menard.module: #{file} written")

      _ ->
        Mix.raise("usage: mix menard.module add FILE CODE  (CODE of `-` reads stdin) | list FILE")
    end
  end
end
