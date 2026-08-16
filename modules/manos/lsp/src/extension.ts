// manos/lsp — give the agent the same language intelligence the editor has, on demand.
// Five pi tools backed by real LSP servers (Expert for Elixir, typescript-language-server
// for TS, nil for Nix, bash-language-server for shell, vscode-json-language-server for
// JSON — see adapters.ts):
//
//   hover(path, line, col)        type/signature/doc at a position
//   definition(path, line, col)   where a symbol is defined (file:line:col)
//   references(path, line, col)   where a symbol is referenced
//   symbols(path)                 the document's outline (functions/types/…)
//   diagnostics(path)             the server's published errors/warnings for a file
//
// The agent calls these WHEN IT NEEDS them — not on every save (a project-wide compile per
// edit is too heavy; the spirit is "don't leave broken code around," and `mix format`
// already covers formatting on save via manos/fmt). LSP gives what bash+mix can't: type
// info, definitions, references, incremental file-scoped diagnostics.
//
// line/col are 1-based (editor convention); converted to 0-based for the protocol. A
// missing server binary surfaces as a clear error, never a hang (every request has a
// timeout in the client). One LspClient per (adapter, project root), reused for the life
// of the pi session — LSP servers are long-lived and index once per project.

import type { ExtensionAPI } from "./pi.ts";
import { Type } from "./pi.ts";
import { adapterForFile, type LanguageAdapter } from "./adapters.ts";
import { LspClient, LspError, type LspPosition } from "./client.ts";
import type { ToolResult } from "./pi.ts";

export default function lsp(pi: ExtensionAPI): void {
  // Cached servers: one per (adapter name, project root). Lives for the session.
  const clients = new Map<string, LspClient>();

  function clientFor(file: string): { client: LspClient; adapter: LanguageAdapter } {
    const adapter = adapterForFile(file);
    if (!adapter) throw new LspError(`no LSP adapter for ${file} (unknown extension)`);
    const root = adapter.rootFor(file);
    if (!root) throw new LspError(`no project root for ${file} (no ${adapter.name} marker found)`);
    const key = `${adapter.name}:${root}`;
    let client = clients.get(key);
    if (!client) {
      client = new LspClient(adapter.command, adapter.args, root);
      // initialize before caching so a bad spawn fails fast, not on the first request.
      // Fire-and-forget the init: the first real request awaits openDoc/the call, which
      // races the init — but LSP servers queue requests until initialized, so this is safe.
      client.initialize().catch(() => {
        /* a failed init surfaces on the next request via a disposed/errored client */
      });
      clients.set(key, client);
    }
    return { client, adapter };
  }

  const pos = (p: Record<string, unknown>): LspPosition => ({
    line: Math.max(0, (Number(p.line) ?? 1) - 1),
    character: Math.max(0, (Number(p.col) ?? 1) - 1),
  });

  const run = async (
    params: Record<string, unknown>,
    fn: (client: LspClient, file: string) => Promise<string>,
  ): Promise<ToolResult> => {
    const file = String(params.path ?? "");
    if (!file) return { content: [{ type: "text", text: "missing `path`" }], isError: true };
    try {
      const { client } = clientFor(file);
      const text = await fn(client, file);
      return { content: [{ type: "text", text }] };
    } catch (err) {
      const msg = err instanceof LspError ? err.message : err instanceof Error ? err.message : String(err);
      return { content: [{ type: "text", text: `lsp: ${msg}` }], isError: true };
    }
  };

  const PathParam = Type.Object({ path: Type.String({ description: "absolute file path" }) });
  const PosParam = Type.Object({
    path: Type.String({ description: "absolute file path" }),
    line: Type.Number({ description: "1-based line number" }),
    col: Type.Number({ description: "1-based column number" }),
  });

  pi.registerTool({
    name: "hover",
    description: "LSP hover: the type/signature/doc at a (path, line, col). 1-based line/col. Routes to the file's language server (Expert for Elixir, typescript-language-server for TS, …).",
    parameters: PosParam,
    execute: (_id, p) => run(p, (c, f) => c.hover(f, pos(p))),
  });
  pi.registerTool({
    name: "definition",
    description: "LSP go-to-definition: where the symbol at (path, line, col) is defined. Returns file:line:col locations. 1-based line/col.",
    parameters: PosParam,
    execute: (_id, p) => run(p, (c, f) => c.definition(f, pos(p))),
  });
  pi.registerTool({
    name: "references",
    description: "LSP references: everywhere the symbol at (path, line, col) is referenced. Returns file:line:col locations. 1-based line/col.",
    parameters: PosParam,
    execute: (_id, p) => run(p, (c, f) => c.references(f, pos(p))),
  });
  pi.registerTool({
    name: "symbols",
    description: "LSP document symbols: the outline of a file (functions, types, modules, …) with their positions.",
    parameters: PathParam,
    execute: (_id, p) => run(p, (c, f) => c.documentSymbol(f)),
  });
  pi.registerTool({
    name: "diagnostics",
    description: "LSP diagnostics: the server's published errors/warnings for a file (incremental, file-scoped — cheaper and finer than a full mix compile / tsc). May be empty until the server has indexed the doc.",
    parameters: PathParam,
    execute: (_id, p) => run(p, (c, f) => Promise.resolve(c.diagnostics(f))),
  });
}