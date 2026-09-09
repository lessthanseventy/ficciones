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

  `visibility` flips a function public/private — EVERY clause of it, since a half-flipped
  function does not compile; going private also drops an attached `@doc`, which Elixir discards
  with a warning. Give it `name_arity` and `visibility`.

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
      values: ["replace", "rewrite", "delete", "insert_after", "insert_before", "insert_at", "visibility"],
      required: true
    )

    field(:file, :string, required: true)
    field(:name_arity, :string)
    field(:head, :string)
    field(:code, :string)
    field(:module, :string)
    field(:at, :enum, values: ["top", "bottom"])
    field(:visibility, :enum, values: ["public", "private"])
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

  defp want("public"), do: :public
  defp want(_private), do: :private

  defp edit(%{verb: verb} = p, source) do
    code = p[:code] || ""

    case verb do
      "replace" -> Clause.replace_body(source, p.name_arity, p.head, code)
      "rewrite" -> Clause.rewrite(source, p.name_arity, p.head, code)
      "delete" -> Clause.delete(source, p.name_arity, p.head)
      "insert_after" -> Clause.insert_after(source, p.name_arity, p.head, code)
      "insert_before" -> Clause.insert_before(source, p.name_arity, p.head, code)
      "insert_at" -> Clause.insert_at(source, p[:module], p[:at], code)
      # every clause of the function at once — a half-flipped one does not compile
      "visibility" -> Clause.visibility(source, p.name_arity, want(p[:visibility]))
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

defmodule Menard.MCP.Directive do
  @moduledoc """
  `alias` / `import` / `require` / `use`, placed where they belong. `verb` is `add` (in sorted
  position inside its own block, opening the block in Elixir's conventional order — use, import,
  alias, require — when there isn't one), `remove`, or `list` (what the module already pulls in).
  `kind` is which directive; `target` the module; `args` the rest as written ("only: [pad: 3]",
  "as: Thing"). Adding one that is already there is a no-op, never a duplicate line. `module` names
  which module in a file that has several.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply

  alias Menard.Directive

  schema do
    field(:verb, :enum, values: ["add", "remove", "list"], required: true)
    field(:file, :string, required: true)
    field(:kind, :enum, values: ["alias", "import", "require", "use"])
    field(:target, :string)
    field(:args, :string)
    field(:module, :string)
  end

  @impl true
  def execute(%{verb: "list"} = params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         found when is_list(found) <- Directive.list(File.read!(file), module: params[:module]) do
      ok(frame, %{"directives" => Enum.map(found, fn {kind, target} -> "#{kind} #{target}" end)})
    else
      {:error, message} -> fail(frame, message)
    end
  end

  def execute(params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         {:ok, kind} <- kind(params[:kind]),
         {:ok, target} <- target(params[:target]),
         out when is_binary(out) <- edit(params.verb, File.read!(file), kind, target, params) do
      File.write!(file, out)
      Menard.format(file)
      ok(frame, %{"did" => "#{params.verb} #{kind} #{target} in #{Path.basename(file)}", "file" => file})
    else
      {:error, message} -> fail(frame, message)
    end
  end

  defp edit("add", source, kind, target, params),
    do: Directive.add(source, kind, target, module: params[:module], args: params[:args])

  defp edit("remove", source, kind, target, params),
    do: Directive.remove(source, kind, target, module: params[:module])

  defp kind(k) when k in ["alias", "import", "require", "use"], do: {:ok, String.to_existing_atom(k)}
  defp kind(_k), do: {:error, "kind is required: alias, import, require or use"}

  defp target(t) when is_binary(t) and t != "", do: {:ok, t}
  defp target(_t), do: {:error, "target is required — the module the directive names"}
end

defmodule Menard.MCP.Attr do
  @moduledoc """
  Module attributes — the tables a module keeps at the top (`@hints`, `@colors`, `@panes`), which
  no clause verb reaches because an attribute is not a clause. `verb` is `get`, `set` (replaces the
  value, or adds the attribute above the first definition when missing), `delete` or `list`.
  Addressed by `name`; a name several attributes share (`@doc`/`@impl`/`@spec` repeat per clause)
  is refused with their lines — those belong to the clause verbs.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply

  alias Menard.Attr

  schema do
    field(:verb, :enum, values: ["get", "set", "delete", "list"], required: true)
    field(:file, :string, required: true)
    field(:name, :string)
    field(:value, :string)
    field(:module, :string)
  end

  @impl true
  def execute(%{verb: verb} = params, frame) when verb in ["get", "list"] do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         source <- File.read!(file),
         result <- read(verb, source, params) do
      case result do
        {:error, :missing} ->
          fail(frame, "no @#{params[:name]} in this module")

        {:error, message} ->
          fail(frame, message)

        found when is_list(found) ->
          ok(frame, %{"attributes" => Enum.map(found, fn {n, l} -> "@#{n} (line #{l})" end)})

        text ->
          ok(frame, %{"value" => text})
      end
    else
      {:error, message} -> fail(frame, message)
    end
  end

  def execute(params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         out when is_binary(out) <- write(params.verb, File.read!(file), params) do
      File.write!(file, out)
      Menard.format(file)
      ok(frame, %{"did" => "#{params.verb} @#{params[:name]} in #{Path.basename(file)}", "file" => file})
    else
      {:error, :missing} -> fail(frame, "no @#{params[:name]} in this module")
      {:error, message} -> fail(frame, message)
    end
  end

  defp read("get", source, p), do: Attr.get(source, p[:name] || "", module: p[:module])
  defp read("list", source, p), do: Attr.list(source, module: p[:module])

  defp write("set", source, p), do: Attr.set(source, p[:name] || "", p[:value] || "", module: p[:module])
  defp write("delete", source, p), do: Attr.delete(source, p[:name] || "", module: p[:module])
end

defmodule Menard.MCP.Block do
  @moduledoc """
  The body of a macro's `do` block — `schema do`, `describe "…" do`, `test "…" do`. Not a clause,
  so no clause verb reaches one. `verb` is `get`, `replace` (body := `code`) or `list`. `label` is
  the macro's first string argument, which is what makes `describe`/`test` addressable; several
  blocks of one name with no label is refused, listing them. `add` writes a NEW block — at the end
  of the block named by `in` (a describe, by its label), else after the last sibling of that name,
  else at the end of the module.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply

  alias Menard.Block

  schema do
    field(:verb, :enum, values: ["get", "replace", "add", "list"], required: true)
    field(:file, :string, required: true)
    field(:name, :string)
    field(:code, :string)
    field(:label, :string)
    field(:in, :string)
    field(:module, :string)
  end

  @impl true
  def execute(%{verb: "list"} = params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         found when is_list(found) <- Block.list(File.read!(file), module: params[:module]) do
      ok(frame, %{"blocks" => Enum.map(found, fn {n, l, line} -> "#{n} #{inspect(l)} (line #{line})" end)})
    else
      {:error, message} -> fail(frame, message)
    end
  end

  def execute(%{verb: "get"} = params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         text when is_binary(text) <- Block.get(File.read!(file), params[:name] || "", where(params)) do
      ok(frame, %{"body" => text})
    else
      {:error, message} -> fail(frame, message)
    end
  end

  def execute(params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         out when is_binary(out) <- edit(params, File.read!(file)) do
      File.write!(file, out)
      Menard.format(file)
      ok(frame, %{"did" => "#{params.verb} #{params[:name]} in #{Path.basename(file)}", "file" => file})
    else
      {:error, message} -> fail(frame, message)
    end
  end

  defp edit(%{verb: "add"} = p, source),
    do: Block.add(source, p[:name] || "", p[:label], p[:code] || "", in: p[:in], module: p[:module])

  defp edit(p, source), do: Block.replace(source, p[:name] || "", p[:code] || "", where(p))

  defp where(params), do: [module: params[:module], label: params[:label]]
end

defmodule Menard.MCP.Deps do
  @moduledoc """
  What one function references — the read that answers "can this move, and what comes with it?".
  Returns the local calls it makes (each with `shared_with`: the OTHER functions here that also
  call it, so a helper with an empty list can travel and one with entries cannot), the remote
  calls, the modules whose aliases must travel, and the attributes it reads — which do not.

  There is no `move` verb on purpose: a move is this report plus `clause insert-at`,
  `directive add`, `clause delete`, `find calls` and `run compile`.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply

  schema do
    field(:file, :string, required: true)
    field(:name_arity, :string, required: true)
    field(:module, :string)
  end

  @impl true
  def execute(params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         %{} = report <- Menard.Deps.of(File.read!(file), params.name_arity, module: params[:module]) do
      ok(frame, report)
    else
      {:error, message} -> fail(frame, message)
    end
  end
end

defmodule Menard.MCP.Module do
  @moduledoc """
  Whole modules inside a file. `add` appends a complete `defmodule` after the last one (a name the
  file already defines is refused); `list` names them. `clause insert_at` puts a function INTO a
  module and `write` replaces a whole file — neither adds a second module to a file that has one.
  """
  use Anubis.Server.Component, type: :tool
  import Menard.MCP.Reply

  schema do
    field(:verb, :enum, values: ["add", "list"], required: true)
    field(:file, :string, required: true)
    field(:code, :string)
  end

  @impl true
  def execute(%{verb: "list"} = params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         names when is_list(names) <- Menard.Module.list(File.read!(file)) do
      ok(frame, %{"modules" => names})
    else
      {:error, message} -> fail(frame, message)
    end
  end

  def execute(params, frame) do
    with {:ok, file} <- Menard.MCP.resolve(params.file),
         out when is_binary(out) <- Menard.Module.add(File.read!(file), params[:code] || "") do
      File.write!(file, out)
      Menard.format(file)
      ok(frame, %{"did" => "add a module to #{Path.basename(file)}", "file" => file})
    else
      {:error, message} -> fail(frame, message)
    end
  end
end
