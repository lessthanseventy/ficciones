// manos/lsp — the pi shim for the manos-lspd sidecar. Registers the same five LSP tools
// (hover/definition/references/symbols/diagnostics) with identical names/schemas, and
// forwards each call over a Unix socket to the long-lived daemon that owns the warm
// LspClient pool. Models see zero change; a pi restart leaves the servers warm.
//
// line/col are 1-based (editor convention); the daemon converts to 0-based for the protocol.

import type { ExtensionAPI, ToolResult } from "./pi.ts";
import { Type } from "./pi.ts";
import { LspdClient, LspdConnectionError } from "./socket.ts";

export default function lsp(pi: ExtensionAPI): void {
  const client = new LspdClient();

  const run = async (params: Record<string, unknown>, method: Parameters<LspdClient["request"]>[0]): Promise<ToolResult> => {
    const file = String(params.path ?? "");
    if (!file) return { content: [{ type: "text", text: "missing `path`" }], isError: true };
    try {
      const text = await client.request(method, params);
      return { content: [{ type: "text", text }] };
    } catch (err) {
      // A dead socket means the daemon isn't up — self-heal (spawn + retry once). A normal
      // LSP error (ok:false) or a hung-daemon timeout is surfaced as-is, no respawn.
      if (err instanceof LspdConnectionError) {
        try {
          const text = await client.selfHeal(method, params);
          return { content: [{ type: "text", text }] };
        } catch (err2) {
          const msg = err2 instanceof Error ? err2.message : String(err2);
          return { content: [{ type: "text", text: `lspd unavailable — ${msg} (mise run lspd:restart)` }], isError: true };
        }
      }
      const msg = err instanceof Error ? err.message : String(err);
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
    execute: (_id, p) => run(p, "hover"),
  });
  pi.registerTool({
    name: "definition",
    description: "LSP go-to-definition: where the symbol at (path, line, col) is defined. Returns file:line:col locations. 1-based line/col.",
    parameters: PosParam,
    execute: (_id, p) => run(p, "definition"),
  });
  pi.registerTool({
    name: "references",
    description: "LSP references: everywhere the symbol at (path, line, col) is referenced. Returns file:line:col locations. 1-based line/col.",
    parameters: PosParam,
    execute: (_id, p) => run(p, "references"),
  });
  pi.registerTool({
    name: "symbols",
    description: "LSP document symbols: the outline of a file (functions, types, modules, …) with their positions.",
    parameters: PathParam,
    execute: (_id, p) => run(p, "symbols"),
  });
  pi.registerTool({
    name: "diagnostics",
    description: "LSP diagnostics: the server's published errors/warnings for a file (incremental, file-scoped — cheaper and finer than a full mix compile / tsc). May be empty until the server has indexed the doc.",
    parameters: PathParam,
    execute: (_id, p) => run(p, "diagnostics"),
  });
}
