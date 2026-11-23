// The pure half of the tell entry: the line goes to `babylon tell`, and what it answers comes back.

/** runs argv, resolves with its exit status and stderr, rejects if it cannot start */
export type Run = (argv: string[]) => Promise<{ code: number; err: string }>

export type Sent = { ok: true } | { ok: false; reason: string }

/** Tell the orchestrator `line`. A refusal is babylon's own first line of stderr. */
export async function sendTell(line: string, run: Run): Promise<Sent> {
  try {
    const { code, err } = await run(["babylon", "tell", line])
    if (code === 0) return { ok: true }
    return { ok: false, reason: err.trim().split("\n")[0] || `babylon tell exited ${code}` }
  } catch (e) {
    return { ok: false, reason: String(e) }
  }
}
