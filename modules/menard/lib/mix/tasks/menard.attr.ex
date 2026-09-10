defmodule Mix.Tasks.Menard.Attr do
  @shortdoc "Module attributes: mix menard.attr get|set|delete|list FILE [NAME] [VALUE]"
  @moduledoc """
  `mix menard.attr get lib/a.ex hints` — the value as written.
  `mix menard.attr set lib/a.ex hints '[{"a", "b"}]'` — replace it, or add it above the first def.
  `mix menard.attr delete lib/a.ex hints` · `mix menard.attr list lib/a.ex`

  The tables a module keeps at the top, which every clause verb walks past because an attribute is
  not a clause. A name several attributes share (`@doc`, `@impl`, `@spec` repeat per clause) is
  refused with their lines — those belong to the clause verbs. `--module Mod.Name` picks one of
  several modules in a file.
  """
  use Mix.Task

  alias Menard.Attr

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [module: :string])
    where = [module: opts[:module]]

    case args do
      ["get", file, name] ->
        report(Attr.get(File.read!(Menard.resolve(file)), name, where))

      ["list", file] ->
        report(list(Attr.list(File.read!(Menard.resolve(file)), where)))

      ["set", file, name, value] ->
        edit(file, &Attr.set(&1, name, value, where))

      ["delete", file, name] ->
        edit(file, &Attr.delete(&1, name, where))

      ["comment", file, name] ->
        edit(file, &Attr.comment(&1, name, nil, where))

      ["comment", file, name, text] ->
        edit(file, &Attr.comment(&1, name, text, where))

      _ ->
        Mix.raise(
          "usage: mix menard.attr (get|set|delete|comment) FILE NAME [VALUE|TEXT] | list FILE [--module Mod]"
        )
    end
  end

  defp list(found) when is_list(found),
    do: Enum.map_join(found, "\n", fn {name, line} -> "@#{name} (line #{line})" end)

  defp list(other), do: other

  defp report({:error, message}), do: Mix.raise(message)
  defp report(:missing), do: Mix.raise("no such attribute")
  defp report(text), do: Mix.shell().info(text)

  defp edit(file, change) do
    file = Menard.resolve(file)

    case change.(File.read!(file)) do
      {:error, :missing} ->
        Mix.raise("no such attribute")

      {:error, message} ->
        Mix.raise(message)

      out ->
        case Menard.checked_write(file, out) do
          :ok -> :ok
          {:error, message} -> Mix.raise(message)
        end
    end

    Mix.shell().info("menard.attr: #{file} written")
  end
end
