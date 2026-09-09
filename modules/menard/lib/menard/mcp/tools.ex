defmodule Menard.MCP.Reply do
  @moduledoc false
  alias Anubis.Server.Response

  def ok(frame, payload), do: {:reply, Response.json(Response.tool(), payload), frame}
  def fail(frame, message), do: {:reply, Response.error(Response.tool(), message), frame}
end

defmodule Menard.MCP.Rename do
  @moduledoc """
  Rename an identifier across files, AST-aware: every def head, call, capture and variable named
  `old` becomes `new`; strings stay; `atoms` also renames `:old`/`old:`, `comments` the whole-word
  mentions in `#` comments. Only the identifier's bytes move. Paths are under the launch root.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply

  schema do
    field(:old, :string, required: true)
    field(:new, :string, required: true)
    field(:files, {:list, :string}, required: true)
    field(:atoms, :boolean)
    field(:comments, :boolean)
  end

  @impl true
  def execute(params, frame) do
    with {:ok, files} <- Menard.MCP.resolve_all(params.files) do
      opts = [atoms: params[:atoms] == true, comments: params[:comments] == true]

      {changed, unchanged} =
        Enum.split_with(files, fn file ->
          source = File.read!(file)

          case Menard.Rename.run(source, params.old, params.new, opts) do
            out when is_binary(out) and out != source -> File.write!(file, out) == :ok
            _ -> false
          end
        end)

      ok(frame, %{"changed" => changed, "unchanged" => unchanged})
    else
      {:error, message} -> fail(frame, message)
    end
  end
end

defmodule Menard.MCP.Clause do
  @moduledoc """
  Edit ONE clause: `verb` is `replace` (body := `code`), `delete`, `insert_after` or
  `insert_before` (`code` is the new clause). Address it by `name_arity` ("go/1", or "Mod.go/1" in
  a file with several modules — an unqualified name that several modules define is refused) and
  `head` — its args as written plus any guard. A miss lists the heads that exist. Only the
  clause's bytes change.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply
  alias Menard.Clause

  schema do
    field(:verb, :enum,
      values: ["replace", "delete", "insert_after", "insert_before"],
      required: true
    )

    field(:file, :string, required: true)
    field(:name_arity, :string, required: true)
    field(:head, :string, required: true)
    field(:code, :string)
  end

  @impl true
  def execute(params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         source <- File.read!(file),
         out when is_binary(out) <-
           edit(params.verb, source, params.name_arity, params.head, params[:code]) do
      File.write!(file, out)
      # the one line a transcript shows: what happened, to which clause, where
      ok(frame, %{
        "did" => "#{params.verb} #{params.name_arity} `#{params.head}` in #{Path.basename(file)}",
        "file" => file
      })
    else
      {:error, message} -> fail(frame, message)
    end
  end

  defp edit("replace", s, na, head, code), do: Clause.replace_body(s, na, head, code || "")
  defp edit("delete", s, na, head, _code), do: Clause.delete(s, na, head)
  defp edit("insert_after", s, na, head, code), do: Clause.insert_after(s, na, head, code || "")
  defp edit("insert_before", s, na, head, code), do: Clause.insert_before(s, na, head, code || "")
end

defmodule Menard.MCP.Outline do
  @moduledoc "A file as an outline: modules, defs with arity/kind/spec/doc, line spans. Read before editing."
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply

  schema do
    field(:file, :string, required: true)
  end

  @impl true
  def execute(%{file: file}, frame) do
    with {:ok, abs} <- Menard.MCP.resolve(file),
         {:ok, modules} <- Menard.Outline.run(File.read!(abs)) do
      ok(frame, %{"file" => abs, "modules" => modules})
    else
      {:error, message} when is_binary(message) -> fail(frame, message)
      {:error, reason} -> fail(frame, "not parseable — #{inspect(reason)}")
    end
  end
end

defmodule Menard.MCP.Find do
  @moduledoc """
  grep that knows the code: `kind` is `calls` (target: "fun" or "Mod.fun", alias-aware), `defs`
  (target: "name" or "name/arity") or `aliases` (target: "Mod.Sub"). Strings and comments never
  match. `files` may be globs, under the launch root.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply

  schema do
    field(:kind, :enum, values: ["calls", "defs", "aliases"], required: true)
    field(:target, :string, required: true)
    field(:files, {:list, :string}, required: true)
  end

  @impl true
  def execute(params, frame) do
    with {:ok, patterns} <- Menard.MCP.resolve_all(params.files) do
      finder =
        case params.kind do
          "calls" -> &Menard.Find.calls(&1, params.target)
          "defs" -> &Menard.Find.defs(&1, params.target)
          "aliases" -> &Menard.Find.aliases(&1, params.target)
        end

      hits =
        patterns
        |> Enum.flat_map(&Path.wildcard/1)
        |> Enum.flat_map(fn file ->
          file |> File.read!() |> finder.() |> Enum.map(&Map.put(&1, :file, file))
        end)

      ok(frame, %{"hits" => hits})
    else
      {:error, message} -> fail(frame, message)
    end
  end
end

defmodule Menard.MCP.Run do
  @moduledoc """
  Run a verb in a mix project under the root and get ONE structured answer: `check` (the
  project's `mix precommit`), `test` (args: files, file:line — each failure as data plus the test's
  source), `format` (args: files), `compile` (warnings as diagnostics). `dir` defaults to the root.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply

  schema do
    field(:verb, :enum, values: ["check", "test", "format", "compile"], required: true)
    field(:args, {:list, :string})
    field(:dir, :string)
  end

  @impl true
  def execute(params, frame) do
    with {:ok, dir} <- Menard.MCP.resolve(params[:dir] || ".") do
      ok(frame, Menard.Run.result(dir, params.verb, params[:args] || []))
    else
      {:error, message} -> fail(frame, message)
    end
  end
end
