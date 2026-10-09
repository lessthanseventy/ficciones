// tlon's alerts (GET /api/alerts, Server.Alerts): what to raise and how loudly — an alarm for a
// meeting about to start, a decision blocking work, a sticky note that stays until seen, an info
// toast that goes by on its own (once per key: it dismisses itself when it goes). Each
// carries its actions as operator-API calls (or a link to open), so every surface acts on any
// alert the same way. Polled every 15 s; dismissing and snoozing are ours, kept in the state dir
// so a restart does not fire them again. An alert whose cause resolves drops off on its own.
import { createState, createComputed } from "ags"
import { interval } from "ags/time"
import { execAsync } from "ags/process"
import { fetch } from "ags/fetch"
import GLib from "gi://GLib?version=2.0"
import { logEvent } from "./log"
import { openInOffice } from "./agents"
import { hypr } from "./hypr"
import { dispatchNow } from "./hyprlua"
import { showing as up, ofLevel, request, type Action, type Alert, type Kept } from "./alerts-core"

export type { Action, Alert }

const API = "http://127.0.0.1:4040"
const STATE = `${GLib.get_user_state_dir()}/astal-shell/alerts.json`
const SNOOZE_S = 5 * 60

function load(): Kept {
  try {
    const [ok, bytes] = GLib.file_get_contents(STATE)
    if (ok) return { dismissed: [], snoozed: {}, ...JSON.parse(new TextDecoder().decode(bytes)) }
  } catch { /* none yet */ }
  return { dismissed: [], snoozed: {} }
}
const [kept, setKept] = createState<Kept>(load())
function save(k: Kept) {
  setKept(k)
  try {
    GLib.mkdir_with_parents(GLib.path_get_dirname(STATE), 0o755)
    GLib.file_set_contents(STATE, JSON.stringify(k))
  } catch (e) { console.error("alerts state:", String(e)) }
}

const [all, setAll] = createState<Alert[]>([])
const [now, setNow] = createState(Date.now() / 1000)
/** decisions folded into the bar's pill ("later") — only for this session */
const [later, setLater] = createState<string[]>([])

const showing = createComputed(() => up(all(), kept(), now()))
export const alarms = showing((as) => ofLevel(as, "alarm"))
export const decisions = showing((as) => ofLevel(as, "decision"))
export const stickies = showing((as) => ofLevel(as, "sticky"))
export const infos = showing((as) => ofLevel(as, "info"))
/** the decision on the banner: the first not folded away */
export const banner = createComputed(() => decisions().find((a) => !later().includes(a.key)) ?? null)
/** how many decisions are folded into the pill */
export const folded = createComputed(() => decisions().filter((a) => later().includes(a.key)).length)

export async function refreshAlerts() {
  try {
    const res = await fetch(`${API}/api/alerts`)
    if (res.status !== 200) return
    const fresh = (await res.json()) as Alert[]
    const prev = all.peek(), was = new Map(prev.map((a) => [a.key, a]))
    for (const a of fresh) if (!was.has(a.key)) logEvent("agent", `${a.level}: ${a.title}`, a.level === "sticky" || a.level === "info" ? "normal" : "warn")
    // an unchanged alert keeps its object: the banner's <With> rebuilds on a new one, which every
    // poll would otherwise do under the pointer — eating a click, wiping a half-typed reply
    const next = fresh.map((a) => { const p = was.get(a.key); return p && JSON.stringify(p) === JSON.stringify(a) ? p : a })
    if (next.length !== prev.length || next.some((a, i) => a !== prev[i])) setAll(next)
    // forget what has dropped off for good, so the state file does not grow forever
    const live = new Set(next.map((a) => a.key)), k = kept.peek()
    if (k.dismissed.some((d) => !live.has(d))) save({ ...k, dismissed: k.dismissed.filter((d) => live.has(d)) })
  } catch { /* the channel is down: keep what is up */ }
  setNow(Date.now() / 1000)
}

export const dismiss = (a: Alert) => save({ ...kept.peek(), dismissed: [...kept.peek().dismissed, a.key] })
export const snooze = (a: Alert, s = SNOOZE_S) => save({ ...kept.peek(), snoozed: { ...kept.peek().snoozed, [a.key]: Date.now() / 1000 + s } })
export const foldAway = (a: Alert) => setLater([...later.peek(), a.key])
export const unfold = () => setLater([])

/** Show thread `tid` where the operator works: the office TUI when its window is up (it polls the
 * server's focus request and opens it), else the rail's office. */
export async function openThread(tid: number) {
  // ghostty puts a 🔔 before the title when the TUI rings, so the end is what names it
  const tui = hypr.get_clients().find((c) => c.title.endsWith("tlon office"))
  if (!tui) return openInOffice(tid)
  await fetch(`${API}/api/office/focus`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ thread_id: tid }) }).catch(() => {})
  dispatchNow(`hl.dsp.focus({ window = "address:0x${tui.address.replace(/^0x/, "")}" })`)
}

/** the doc the reader sheet shows (surfaces/DocReader.tsx), or null when it is closed */
export const [doc, setDoc] = createState<{ title: string; text: string } | null>(null)
export const closeDoc = () => setDoc(null)

/** a doc (an alert's Read it), opened in the shell's own reader */
async function readDoc(a: Alert, path: string) {
  const res = await fetch(`${API}${path}`)
  if (res.status !== 200) throw new Error(`no doc (HTTP ${res.status})`)
  const { text } = (await res.json()) as { name: string; text: string }
  setDoc({ title: `${a.thread_id ? `#${a.thread_id} ` : ""}${a.title}`, text })
}

/** Do what an action says: open its link, read its doc, or make its call (with `text` in its `input` field). */
export async function act(a: Alert, x: Action, text?: string) {
  try {
    if (x.open) { await execAsync(["xdg-open", x.open]); dismiss(a); return }
    if (x.read) { await readDoc(a, x.read); return }
    const call = request(x, text)
    if (!call) return
    const res = await fetch(`${API}${call.path}`, { method: call.method, headers: { "content-type": "application/json" }, body: JSON.stringify(call.body) })
    if (res.status >= 300) throw new Error(`HTTP ${res.status}`)
    logEvent("agent", `${x.label}: ${a.title}`)
    dismiss(a)
  } catch (e) {
    logEvent("agent", `${x.label} failed: ${String(e)}`, "warn")
  }
  void refreshAlerts()
}

export function startAlerts() {
  void refreshAlerts()
  interval(15_000, () => void refreshAlerts())
  // a snooze ends on time even between polls
  interval(5_000, () => setNow(Date.now() / 1000))
}
