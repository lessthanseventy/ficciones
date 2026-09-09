defmodule Mix.Tasks.Menard.Block do
  @shortdoc "A macro's do-block: mix menard.block get|replace|list FILE NAME [CODE] [--label X]"
  @moduledoc """
  `mix menard.block replace lib/a.ex schema 'field(:x, :string)'` — swap a `schema do … end` body.
  `mix menard.block add test/a_test.exs test 'assert 1 == 1' --label "it works" --in "the leader"`
  `mix menard.block get test/a_test.exs describe --label 'the leader'` · `mix menard.block list FILE`

  A macro call's body is not a clause, so no clause verb reaches one. `--label` is the macro's
  first string argument, which is what makes `describe "…"` and `test "…"` addressable; several
  blocks of one name with no label given is refused, listing them.
  """
  use Mix.Task

  alias Menard.Block

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [module: :string, label: :string, in: :string])
    where = [module: opts[:module], label: opts[:label]]

    case args do
      ["get", file, name] ->
        report(Block.get(File.read!(Menard.resolve(file)), name, where))

      ["relabel", file, name, label, new_label] ->
        edit(file, &Block.relabel(&1, name, label, new_label, module: opts[:module]))

      ["list", file] ->
        report(list(Block.list(File.read!(Menard.resolve(file)), where)))

      ["replace", file, name, code] ->
        edit(file, &Block.replace(&1, name, code, where))

      ["add", file, name, code] ->
        edit(file, &Block.add(&1, name, opts[:label], code, in: opts[:in], module: opts[:module]))

      _ ->
        Mix.raise(
          "usage: mix menard.block (get|replace) FILE NAME [CODE] [--label X]\n" <>
            "       mix menard.block add FILE NAME CODE [--label X] [--in PARENT_LABEL]\n" <>
            "       mix menard.block relabel FILE NAME OLD_LABEL NEW_LABEL\n" <>
            "       mix menard.block list FILE [--module Mod]"
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
      {:error, message} ->
        Mix.raise(message)

      out ->
        case Menard.checked_write(file, out) do
          :ok -> :ok
          {:error, message} -> Mix.raise(message)
        end
    end

    Mix.shell().info("menard.block: #{file} written")
  end
end
