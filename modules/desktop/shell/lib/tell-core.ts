// The pure half of the tell entry: the line goes to `babylon tell` (work) or `asterion -- --tell` (the house), and what it answers comes back.

/** runs argv, resolves with its exit status and stderr, rejects if it cannot start */
export type Run = (argv: string[]) => Promise<{ code: number; err: string }>

export type Dest = "work" | "house"

const argvFor = (dest: Dest, line: string) => (dest === "house" ? ["asterion", "--", "--tell", line] : ["babylon", "tell", line])

export type Sent = { ok: true } | { ok: false; reason: string }

/** Tell `dest` the `line`. A refusal is the command's own first line of stderr. */
export async function sendTell(line: string, run: Run, dest: Dest = "work"): Promise<Sent> {
  try {
    const { code, err } = await run(argvFor(dest, line))
    if (code === 0) return { ok: true }
    return { ok: false, reason: err.trim().split("\n")[0] || `${argvFor(dest, "")[0]} tell exited ${code}` }
  } catch (e) {
    return { ok: false, reason: String(e) }
  }
}
