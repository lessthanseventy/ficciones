// The deck's timer: a countdown ("25m", "1h10", "90s"), an alarm at a clock time ("14:30"),
// or a pomodoro (work/break rounds, "pomo", "pomo 50/10"). One at a time. The row shows what
// is left; the end is a critical notice, so it pins to the deck until you click it.
import { createState } from "ags"
import { execAsync } from "ags/process"
import { interval, type Timer as T } from "ags/time"
import { logEvent } from "./log"
import { duration } from "./format"
import { play } from "./sfx"

export type Kind = "countdown" | "alarm" | "pomodoro"
export type Timer = {
  kind: Kind
  label: string
  endsAt: number
  /** pomodoro only */
  phase?: "work" | "break"
  round?: number
  work?: number // minutes
  rest?: number
}
export const [timer, setTimer] = createState<Timer | null>(null)
/** seconds left, ticked once a second while a timer runs */
export const [left, setLeft] = createState(0)

let tick: T | null = null

/** "25m" "1h10" "1h 10m" "90s" → seconds; null if it is not a duration ("1:30" is a clock time) */
export function parseDuration(s: string): number | null {
  s = s.trim().toLowerCase()
  let m = s.match(/^(\d+)\s*h(?:\s*(\d+)\s*m?)?$/)
  if (m) return Number(m[1]) * 3600 + Number(m[2] ?? 0) * 60
  m = s.match(/^(\d+)\s*m(?:in)?$/); if (m) return Number(m[1]) * 60
  m = s.match(/^(\d+)\s*s(?:ec)?$/); if (m) return Number(m[1])
  return null
}
/** "14:30" "2:30pm" "9pm" → the next such clock time, ms since epoch; null if not a clock time */
export function parseClock(s: string): number | null {
  const m = s.trim().toLowerCase().match(/^(\d{1,2})(?::(\d\d))?\s*(am|pm)?$/)
  if (!m || (!m[2] && !m[3])) return null
  let h = Number(m[1]); const min = Number(m[2] ?? 0)
  if (m[3] === "pm" && h < 12) h += 12
  if (m[3] === "am" && h === 12) h = 0
  if (h > 23 || min > 59) return null
  const d = new Date(); d.setHours(h, min, 0, 0)
  if (d.getTime() <= Date.now()) d.setDate(d.getDate() + 1)
  return d.getTime()
}

/**
 * What a launcher line means, or null: "25m" / "timer 25m" → countdown, "14:30" / "alarm 9pm"
 * → alarm, "pomo" / "pomodoro 50/10" → pomodoro, "stop" while one runs → stop.
 */
export function parseSpec(q: string): { title: string; start: () => void } | null {
  const s = q.trim().toLowerCase().replace(/^(timer|alarm)\s+/, "")
  if (/^(stop|cancel)( timer)?$/.test(s) && timer.peek()) return { title: "stop the timer", start: stopTimer }
  const pomo = s.match(/^pomo(?:doro)?(?:\s+(\d+)\s*\/\s*(\d+))?$/)
  if (pomo) { const w = Number(pomo[1] ?? 25), r = Number(pomo[2] ?? 5); return { title: `pomodoro ${w}/${r}`, start: () => startPomodoro(w, r) } }
  const d = parseDuration(s)
  if (d) return { title: `timer ${duration(d)}`, start: () => startCountdown(d, s) }
  const at = parseClock(s)
  if (at) return { title: `alarm at ${new Date(at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`, start: () => startAlarm(at) }
  return null
}

function run(t: Timer) {
  setTimer(t)
  setLeft((t.endsAt - Date.now()) / 1000)
  tick?.cancel()
  tick = interval(1000, () => {
    const cur = timer.peek()
    if (!cur) { tick?.cancel(); tick = null; return }
    const s = (cur.endsAt - Date.now()) / 1000
    setLeft(s)
    if (s <= 0) fire(cur)
  })
}

function notify(summary: string, body: string, critical = true) {
  execAsync(["notify-send", "-a", "timer", "-u", critical ? "critical" : "normal", "-i", "alarm-symbolic", summary, body]).catch(console.error)
}

function fire(t: Timer) {
  play("timer")
  if (t.kind === "pomodoro") {
    const next: Timer = t.phase === "work"
      ? { ...t, phase: "break", endsAt: Date.now() + (t.round! % 4 === 0 ? 15 : t.rest!) * 60_000 }
      : { ...t, phase: "work", round: t.round! + 1, endsAt: Date.now() + t.work! * 60_000 }
    notify(t.phase === "work" ? `break — round ${t.round} done` : `work — round ${next.round}`, `pomodoro ${t.work}/${t.rest}`, false)
    logEvent("shell", `pomodoro: ${next.phase} (round ${next.round})`)
    run(next)
    return
  }
  notify(t.kind === "alarm" ? "alarm" : "time's up", t.label)
  logEvent("shell", `${t.kind} done: ${t.label}`, "crit")
  stopTimer(true)
}

export function startCountdown(seconds: number, label = duration(seconds)) {
  logEvent("shell", `timer ${duration(seconds)}`)
  run({ kind: "countdown", label, endsAt: Date.now() + seconds * 1000 })
}
export function startAlarm(at: number) {
  const label = new Date(at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  logEvent("shell", `alarm at ${label}`)
  run({ kind: "alarm", label, endsAt: at })
}
export function startPomodoro(work = 25, rest = 5) {
  logEvent("shell", `pomodoro ${work}/${rest}`)
  run({ kind: "pomodoro", label: `pomodoro ${work}/${rest}`, phase: "work", round: 1, work, rest, endsAt: Date.now() + work * 60_000 })
}
export function stopTimer(ended = false) {
  const t = timer.peek()
  if (t && !ended) logEvent("shell", `${t.kind} stopped`, "dim")
  tick?.cancel(); tick = null
  setTimer(null); setLeft(0)
}
