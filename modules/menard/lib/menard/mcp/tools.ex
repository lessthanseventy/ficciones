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

      # The CLI formatted after an edit and this door did not, so the same verb left differently
      # shaped code depending on which door ran it.
      Enum.each(changed, &Menard.format/1)

      ok(frame, %{"changed" => changed, "unchanged" => unchanged})
    else
      {:error, message} -> fail(frame, message)
    end
  end
end

defmodule Menard.MCP.Clause do
  @moduledoc """
  Edit ONE clause. `verb` is `replace` (its body := `code`), `rewrite` (the WHOLE clause, head
  included — the verb for changing args or adding a guard), `delete`, `insert_after` or
  `insert_before` (`code` is the new clause). Address it by `name_arity` ("go/1", or "Mod.go/1" in
  a file with several modules — an unqualified name that several modules define is refused) and
  `head` — its args as written plus any guard, parens optional. A miss lists the heads that exist.
  Only the clause's bytes change.

  `insert_at` is the one verb that takes no clause: it adds a function that has NO sibling to
  anchor to. Give it `module` ("Mod.Name", or omit it in a single-module file) and `code`;
  placement follows the code — a `defp` lands with the other private functions, a `def` with the
  public ones — unless `at` ("top"/"bottom") overrides it.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply
  alias Menard.Clause

  schema do
    field(:verb, :enum,
      values: ["replace", "rewrite", "delete", "insert_after", "insert_before", "insert_at"],
      required: true
    )

    field(:file, :string, required: true)
    field(:name_arity, :string)
    field(:head, :string)
    field(:code, :string)
    field(:module, :string)
    field(:at, :enum, values: ["top", "bottom"])
  end

  @impl true
  def execute(params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         source <- File.read!(file),
         out when is_binary(out) <- edit(params, source) do
      File.write!(file, out)
      # The CLI formatted after an edit and this door did not — same verb, differently shaped code.
      Menard.format(file)

      # the one line a transcript shows: what happened, to which clause, where
      ok(frame, %{
        "did" =>
          "#{params.verb} #{params[:name_arity] || params[:module] || "-"} `#{params[:head] || params[:at]}` in #{Path.basename(file)}",
        "file" => file
      })
    else
      {:error, message} -> fail(frame, message)
    end
  end

  defp edit(%{verb: verb} = p, source) do
    code = p[:code] || ""

    case verb do
      "replace" -> Clause.replace_body(source, p.name_arity, p.head, code)
      "rewrite" -> Clause.rewrite(source, p.name_arity, p.head, code)
      "delete" -> Clause.delete(source, p.name_arity, p.head)
      "insert_after" -> Clause.insert_after(source, p.name_arity, p.head, code)
      "insert_before" -> Clause.insert_before(source, p.name_arity, p.head, code)
      "insert_at" -> Clause.insert_at(source, p[:module], p[:at], code)
    end
  end
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

defmodule Menard.MCP.Write do
  @moduledoc """
  Write a WHOLE file: `code` becomes the entire content of `file`. The verb for what the clause
  verbs structurally cannot do — a NEW module has no clause to address and no file to patch — and
  for a rewrite so total that patching is the wrong tool (a fixture, a generated table). Elixir
  that does not parse is refused before it reaches disk; the file is then formatted with the
  target project's own formatter.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply

  schema do
    field(:file, :string, required: true)
    field(:code, :string, required: true)
  end

  @impl true
  def execute(%{file: file, code: code}, frame) do
    with {:ok, abs} <- Menard.MCP.resolve(file),
         {:ok, what} <- Menard.Write.run(abs, code) do
      if what != :unchanged, do: Menard.format(abs)
      ok(frame, %{"did" => "#{what} #{Path.basename(abs)}", "file" => abs})
    else
      {:error, message} -> fail(frame, message)
    end
  end
end
