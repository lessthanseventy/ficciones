defmodule Mix.Tasks.Menard.Block do
  @shortdoc "A macro's do-block: mix menard.block get|replace|list FILE NAME [CODE] [--label X]"
  @moduledoc """
  `mix menard.block replace lib/a.ex schema 'field(:x, :string)'` — swap a `schema do … end` body.
  `mix menard.block get test/a_test.exs describe --label 'the leader'` · `mix menard.block list FILE`

  A macro call's body is not a clause, so no clause verb reaches one. `--label` is the macro's
  first string argument, which is what makes `describe "…"` and `test "…"` addressable; several
  blocks of one name with no label given is refused, listing them.
  """
  use Mix.Task

  alias Menard.Block

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [module: :string, label: :string])
    where = [module: opts[:module], label: opts[:label]]

    case args do
      ["get", file, name] ->
        report(Block.get(File.read!(Menard.resolve(file)), name, where))

      ["list", file] ->
        report(list(Block.list(File.read!(Menard.resolve(file)), where)))

      ["replace", file, name, code] ->
        edit(file, &Block.replace(&1, name, code, where))

      _ ->
        Mix.raise(
          "usage: mix menard.block (get|replace) FILE NAME [CODE] | list FILE [--label X] [--module Mod]"
        )
    end
  end

  defp list(found) when is_list(found) do
    Enum.map_join(found, "\n", fn
      {name, nil, line} -> "#{name} (line #{line})"
      {name, label, line} -> "#{name} #{inspect(label)} (line #{line})"
    end)
  end

  defp list(other), do: other

  defp report({:error, message}), do: Mix.raise(message)
  defp report(text), do: Mix.shell().info(text)

  defp edit(file, change) do
    file = Menard.resolve(file)

    case change.(File.read!(file)) do
      {:error, message} -> Mix.raise(message)
      out -> File.write!(file, out)
    end

    Menard.format(file)
    Mix.shell().info("menard.block: #{file} written")
  end
end
