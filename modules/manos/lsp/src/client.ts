// A minimal LSP client over stdio — the base protocol (Content-Length framing) on top of
// JSON-RPC. One LspClient per (adapter, project root): spawned once, initialized, then
// reused for every request on a file under that root. The extension holds a cache of them.
//
// Deliberately small, not a general LSP framework: it does the initialize handshake,
// textDocument/didOpen, and the four requests we expose (hover/definition/references/
// documentSymbol). publishDiagnostics notifications are collected per-file so the
// `diagnostics` tool can return them without a round-trip. Every request has a timeout —
// an LSP server must never hang the agent. Any failure throws; the extension turns it into
// a tool error string, never a silent hang.
//
// See https://microsoft.github.io/language-server-protocol/ for the protocol. We target
// the 3.17 request/response shapes; servers broadly agree.

import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import * as fs from "node:fs";

export interface LspPosition {
  line: number; // 0-based
  character: number; // 0-based
}

export interface LspLocation {
  uri: string;
  range: { start: LspPosition; end: LspPosition };
}

export class LspError extends Error {}

interface Pending {
  resolve: (result: unknown) => void;
  reject: (err: unknown) => void;
  timer: ReturnType<typeof setTimeout>;
}

export class LspClient {
  #proc: ChildProcessWithoutNullStreams;
  #buf = "";
  #nextId = 1;
  #pending = new Map<number, Pending>();
  #open = new Set<string>(); // textDocument uris we've sent didOpen for
  #diagnostics = new Map<string, Array<{ severity: number; message: string; range: { start: LspPosition; end: LspPosition } }>>();
  #disposed = false;
  #root: string;

  constructor(command: string, args: string[], root: string) {
    this.#root = root;
    try {
      this.#proc = spawn(command, args, { cwd: root, stdio: ["pipe", "pipe", "pipe"] });
    } catch (err) {
      throw new LspError(`failed to spawn ${command}: ${err instanceof Error ? err.message : String(err)}`);
    }
    this.#proc.stdout.setEncoding("utf-8");
    this.#proc.stdout.on("data", (chunk: string) => this.#onData(chunk));
    this.#proc.on("exit", (code) => {
      if (!this.#disposed) {
        // Server died unexpectedly — fail any pending requests so the tool errors, not hangs.
        for (const p of this.#pending.values()) {
          clearTimeout(p.timer);
          p.reject(new LspError(`${command} exited (code ${code})`));
        }
        this.#pending.clear();
      }
    });
  }

  // The initialize handshake + the initialized notification. Must be the first call.
  async initialize(): Promise<void> {
    const result = await this.#request("initialize", {
      processId: process.pid,
      rootUri: uri(this.#root),
      capabilities: {
        textDocument: {
          hover: { contentFormat: ["markdown", "plaintext"] },
          synchronization: { didOpen: true, didChange: false, didSave: false },
          publishDiagnostics: { relatedInformation: false },
        },
      },
    });
    // Some servers send diagnostics before initialized; the notification is still required.
    void result;
    this.#notify("initialized", {});
  }

  // Open a file in the server (idempotent — didOpen is sent once per uri). The server
  // indexes it and emits publishDiagnostics, which we collect.
  openDoc(absPath: string): void {
    const textDoc = uri(absPath);
    if (this.#open.has(textDoc)) return;
    const text = fs.readFileSync(absPath, "utf-8");
    this.#notify("textDocument/didOpen", {
      textDocument: { uri: textDoc, languageId: langId(absPath), version: 1, text },
    });
    this.#open.add(textDoc);
  }

  async hover(absPath: string, pos: LspPosition): Promise<string> {
    this.openDoc(absPath);
    const r = await this.#request("textDocument/hover", {
      textDocument: { uri: uri(absPath) },
      position: pos,
    });
    return stringifyHover(r);
  }

  async definition(absPath: string, pos: LspPosition): Promise<string> {
    this.openDoc(absPath);
    const r = await this.#request("textDocument/definition", {
      textDocument: { uri: uri(absPath) },
      position: pos,
    });
    return stringifyLocations(r);
  }

  async references(absPath: string, pos: LspPosition): Promise<string> {
    this.openDoc(absPath);
    const r = await this.#request("textDocument/references", {
      textDocument: { uri: uri(absPath) },
      position: pos,
      context: { includeDeclaration: true },
    });
    return stringifyLocations(r);
  }

  async documentSymbol(absPath: string): Promise<string> {
    this.openDoc(absPath);
    const r = await this.#request("textDocument/documentSymbol", {
      textDocument: { uri: uri(absPath) },
    });
    return stringifySymbols(r);
  }

  // The latest diagnostics the server has published for a file (collected from
  // publishDiagnostics notifications). Empty until the server has indexed the doc.
  diagnostics(absPath: string): string {
    const list = this.#diagnostics.get(uri(absPath)) ?? [];
    if (list.length === 0) return "(no diagnostics published yet — server may still be indexing)";
    return list
      .map((d) => {
        const sev = ["Error", "Warning", "Information", "Hint"][d.severity - 1] ?? "Diagnostic";
        return `${sev} at ${d.range.start.line + 1}:${d.range.start.character + 1} — ${d.message}`;
      })
      .join("\n");
  }

  // Stop the server. Called when the extension is done with it (or on a timeout sweep).
  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    try {
      this.#notify("shutdown", {});
      void this.#request("exit", {}).catch(() => {});
    } catch {
      /* best-effort */
    }
    this.#proc.kill("SIGTERM");
  }

  // ── the JSON-RPC base protocol ─────────────────────────────────────────────────────

  #onData(chunk: string): void {
    this.#buf += chunk;
    // Parse as many complete frames as the buffer holds.
    for (;;) {
      const headerEnd = this.#buf.indexOf("\r\n\r\n");
      if (headerEnd < 0) return;
      const headers = this.#buf.slice(0, headerEnd);
      const m = /content-length:\s*(\d+)/i.exec(headers);
      if (!m) {
        // Unframed junk — drop the headers and continue (some servers print a banner).
        this.#buf = this.#buf.slice(headerEnd + 4);
        continue;
      }
      const len = parseInt(m[1]!, 10);
      const bodyStart = headerEnd + 4;
      if (this.#buf.length < bodyStart + len) return; // wait for the full body
      const body = this.#buf.slice(bodyStart, bodyStart + len);
      this.#buf = this.#buf.slice(bodyStart + len);
      this.#dispatch(body);
    }
  }

  #dispatch(body: string): void {
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(body);
    } catch {
      return; // malformed frame — ignore
    }
    if (msg.method === "textDocument/publishDiagnostics" && !("id" in msg)) {
      const params = msg.params as { uri: string; diagnostics: Array<{ severity: number; message: string; range: { start: LspPosition; end: LspPosition } }> };
      this.#diagnostics.set(params.uri, params.diagnostics);
      return;
    }
    if (typeof msg.id === "number" && this.#pending.has(msg.id)) {
      const p = this.#pending.get(msg.id)!;
      this.#pending.delete(msg.id);
      clearTimeout(p.timer);
      if (msg.error) p.reject(new LspError(JSON.stringify(msg.error)));
      else p.resolve(msg.result);
    }
  }

  #request(method: string, params: unknown, timeoutMs = 15_000): Promise<unknown> {
    return new Promise((resolve, reject) => {
      if (this.#disposed) {
        reject(new LspError(`${method}: server disposed`));
        return;
      }
      const id = this.#nextId++;
      const timer = setTimeout(() => {
        this.#pending.delete(id);
        reject(new LspError(`${method} timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      this.#pending.set(id, { resolve, reject, timer });
      this.#write({ jsonrpc: "2.0", id, method, params });
    });
  }

  #notify(method: string, params: unknown): void {
    this.#write({ jsonrpc: "2.0", method, params });
  }

  #write(msg: Record<string, unknown>): void {
    const json = JSON.stringify(msg);
    const frame = `Content-Length: ${Buffer.byteLength(json)}\r\n\r\n${json}`;
    this.#proc.stdin.write(frame);
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────────────

function uri(absPath: string): string {
  return "file://" + absPath;
}

// The languageId the server expects for didOpen. Rough but works for the languages we serve.
function langId(absPath: string): string {
  const ext = absPath.toLowerCase().split(".").pop() ?? "";
  if (["ex", "exs"].includes(ext)) return "elixir";
  if (["heex", "eex", "leex"].includes(ext)) return "eex";
  if (["ts", "tsx", "mts", "cts"].includes(ext)) return "typescript";
  if (["js", "jsx", "mjs", "cjs"].includes(ext)) return "javascript";
  if (ext === "nix") return "nix";
  if (["sh", "bash"].includes(ext)) return "shellscript";
  if (ext === "json") return "json";
  return "plaintext";
}

function stringifyHover(result: unknown): string {
  if (!result) return "(no hover info)";
  const hover = result as { contents?: unknown };
  const c = hover.contents;
  if (typeof c === "string") return c;
  if (c && typeof c === "object" && "value" in c) return String((c as { value: string }).value);
  if (Array.isArray(c)) return c.map(stringifyHover).join("\n\n");
  return JSON.stringify(c);
}

function stringifyLocations(result: unknown): string {
  if (!result) return "(no results)";
  const locs = Array.isArray(result) ? (result as LspLocation[]) : [result as LspLocation];
  if (locs.length === 0) return "(no results)";
  return locs
    .map((l) => {
      const file = l.uri.replace(/^file:\/\//, "");
      return `${file}:${l.range.start.line + 1}:${l.range.start.character + 1}`;
    })
    .join("\n");
}

function stringifySymbols(result: unknown): string {
  if (!result || !Array.isArray(result)) return "(no symbols)";
  const syms = result as Array<{ name: string; kind: number; range?: { start: LspPosition }; children?: unknown[] }>;
  if (syms.length === 0) return "(no symbols)";
  // DocumentSymbol kinds: 1=File,2=Module,3=Namespace,5=Class,6=Method,12=Function,13=Field,14=Property…
  return syms.map((s) => `${symKind(s.kind)} ${s.name}${s.range ? ` (${s.range.start.line + 1}:${s.range.start.character + 1})` : ""}`).join("\n");
}

function symKind(k: number): string {
  return (
    [, "File", "Module", "Namespace", "Package", "Class", "Method", "Property", "Field", "Constructor", "Enum", "Interface", "Function", "Variable", "Constant", "String", "Number", "Boolean", "Array"][k] ?? "Symbol"
  );
}