// The next calendar event and how long until it — the bar's centre cell. khal's --json output
// (start as an ISO time, title); nothing when no calendar is configured or nothing is due
// today. Polled every minute; the countdown ticks off the same accessor.
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"

export type NextUp = { title: string; at: number } | null

export const nextUp = createPoll<NextUp>(null, 60_000, async () => {
  try {
    const out = (await execAsync(["khal", "list", "--json", "start", "--json", "title", "now", "1d"])).trim()
    if (!out) return null
    const rows: { start?: string; title?: string }[] = JSON.parse(out.startsWith("[") ? out : `[${out.split("\n").join(",")}]`).flat()
    const now = Date.now()
    const soon = rows
      .map((r) => ({ title: r.title ?? "", at: Date.parse(r.start ?? "") }))
      .filter((r) => r.title && !Number.isNaN(r.at) && r.at > now - 5 * 60_000)
      .sort((a, b) => a.at - b.at)[0]
    return soon ?? null
  } catch { return null }
})

/** "in 12m" / "in 2h05" / "now" / "3m ago" */
export const untilText = (at: number, now = Date.now()) => {
  const m = Math.round((at - now) / 60_000)
  if (m <= 0 && m > -5) return "now"
  if (m < 0) return `${-m}m ago`
  if (m < 60) return `in ${m}m`
  return `in ${Math.floor(m / 60)}h${String(m % 60).padStart(2, "0")}`
}
