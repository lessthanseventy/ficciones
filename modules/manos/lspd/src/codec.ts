// The manos-lspd wire protocol: length-prefixed JSON over a Unix socket, one message per
// tool op. A 4-byte big-endian length prefix + the UTF-8 JSON body — unambiguous framing
// (no escaping issues, unlike newline-delimited). Pure + unit-tested: the daemon and the
// pi shim both speak it, so this codec is the one seam that must not drift.

export interface LspdRequest {
  id: number;
  method: "hover" | "definition" | "references" | "symbols" | "diagnostics";
  params: { path: string; line?: number; col?: number };
}

export type LspdResponse =
  | { id: number; ok: true; text: string }
  | { id: number; ok: false; error: string };

export function encode(msg: LspdRequest | LspdResponse): Buffer {
  const body = Buffer.from(JSON.stringify(msg), "utf-8");
  const len = Buffer.alloc(4);
  len.writeUInt32BE(body.length, 0);
  return Buffer.concat([len, body]);
}

// Accumulate chunks and yield complete messages. Handles a message split across chunks and
// several messages arriving in one chunk — the two real-world cases on a streamed socket.
export class Decoder {
  #buf: Buffer = Buffer.alloc(0);

  push(chunk: Buffer): unknown[] {
    this.#buf = this.#buf.length === 0 ? chunk : Buffer.concat([this.#buf, chunk]);
    const out: unknown[] = [];
    for (;;) {
      if (this.#buf.length < 4) return out;
      const len = this.#buf.readUInt32BE(0);
      if (this.#buf.length < 4 + len) return out;
      const body = this.#buf.subarray(4, 4 + len).toString("utf-8");
      this.#buf = this.#buf.subarray(4 + len);
      out.push(JSON.parse(body));
    }
  }
}
