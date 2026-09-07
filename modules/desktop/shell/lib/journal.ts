// The last few journal lines at warning and above (system + this user), every 20 s. Errors
// do not hide: the dashboard's JOURNAL card reads them.
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import { logEvent, unitName } from "./log"

export type Entry = { t: string; unit: string; msg: string; prio: number }

async function tail(args: string[]): Promise<Entry[]> {
  const out = await execAsync(["journalctl", ...args, "-p", "4", "-n", "12", "-o", "json", "-q", "--no-pager"])
  return out.trim().split("\n").filter(Boolean).flatMap((l) => {
    try {
      const j = JSON.parse(l)
      const us = Number(j.__REALTIME_TIMESTAMP ?? 0)
      const d = new Date(us / 1000)
      const msg = typeof j.MESSAGE === "string" ? j.MESSAGE : "(binary)"
      return [{ t: `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`, us, unit: unitName(String(j.SYSLOG_IDENTIFIER ?? j._SYSTEMD_UNIT ?? "?")), msg: msg.replace(/\s+/g, " "), prio: Number(j.PRIORITY ?? 4) } as Entry & { us: number }]
    } catch { return [] }
  })
}

let seenUs = 0
export const journal = createPoll<{ ok: boolean; lines: Entry[] }>({ ok: true, lines: [] }, 20_000, async () => {
  try {
    const [sys, usr] = await Promise.all([tail([]).catch(() => []), tail(["--user"]).catch(() => [])])
    const all = [...sys, ...usr] as (Entry & { us: number })[]
    all.sort((a, b) => b.us - a.us)
    // new lines since the last poll feed the command log (errors red, warnings dim); the
    // first poll sets the mark without replaying the backlog
    // (lib/log backfills the past at start; from here on only what is new)
    if (seenUs) for (const e of [...all].reverse()) if (e.us > seenUs) logEvent("journal", `${e.unit}: ${e.msg}`, e.prio <= 3 ? "crit" : "dim")
    if (all[0]) seenUs = Math.max(seenUs, all[0].us)
    else seenUs = seenUs || 1
    return { ok: true, lines: all.slice(0, 6) }
  } catch {
    return { ok: false, lines: [] }
  }
})
