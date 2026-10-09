// The Tlön roster + thread counts for the AGENTS pane and the office, and everything the office
// does: the always-up service's operator API (/api/*, Server.MCP.OperatorAPI) — the snapshot is
// GET /api/office (Server.Office.status, the same read the office TUI makes). Polled every 30 s,
// and at once after a write (`refreshAgents`); "channel down" when the server is not up.
import { createState } from "ags"
import { interval } from "ags/time"
import { execAsync } from "ags/process"
import { fetch } from "ags/fetch"
import GLib from "gi://GLib?version=2.0"
import { logEvent } from "./log"

// the snapshot's shape is tlon's (office/kit/types.ts, Server.Office's contract), shared with
// every office surface
import type { Agents, ThreadView } from "../office/kit/types"
export type { Agents, Archetype, Coworker, ModelChoice, ModelSpec, Note, Seat, Thread, ThreadView, Ticket, Visit } from "../office/kit/types"
/** a thread's brief, the scope get_dossier hands an agent (GET /api/threads/:id) */
export type Dossier = {
  thread_id: number
  goal: string | null
  lead: string | null
  next: string | null
  recent: { at: string; author: string; body: string }[]
  blockers: { shown: { text?: string; title?: string }[]; more: number }
  todos?: { shown: { text?: string; title?: string }[]; more: number }
  done: { shown: unknown[]; more: number }
}
export async function dossier(id: number): Promise<Dossier | null> {
  try {
    const res = await fetch(`${API}/threads/${id}`)
    return res.status === 200 ? ((await res.json()) as Dossier) : null
  } catch { return null }
}
export async function threadView(id: number): Promise<ThreadView | null> {
  try {
    const res = await fetch(`${API}/office/threads/${id}`)
    return res.status === 200 ? ((await res.json()) as ThreadView) : null
  } catch { return null }
}

/** a call to the operator API: its JSON on success, else the error it gave */
async function call(method: string, path: string, body?: unknown): Promise<any> {
  const res = await fetch(`${API}${path}`, { method, headers: { "content-type": "application/json" }, body: JSON.stringify(body ?? {}) })
  const j: any = await res.json().catch(() => null)
  if (res.status >= 300) throw new Error(j?.error ?? `HTTP ${res.status}`)
  return j
}
/** a write: what happened goes to the command log, then the office looks again */
async function write(method: string, path: string, body: unknown, what: string, done: (j: any) => string): Promise<boolean> {
  try {
    logEvent("agent", done(await call(method, path, body)))
    await refreshAgents()
    return true
  } catch (e) {
    logEvent("agent", `${what} failed: ${String(e)}`, "warn")
    return false
  }
}
/** Post to a thread as the operator. A body naming an open prompt's option answers it. */
export const post = (id: number, body: string) => write("POST", `/threads/${id}/messages`, { body }, `post to #${id}`, () => `you → #${id}: ${body}`)
export const fileTicket = (ws: number, project: number | null, title: string, body: string) =>
  write("POST", "/tickets", { workspace_id: ws, project_id: project, title, body }, "filing a ticket", (t) => `filed ticket #${t.id} — ${t.title}`)
/** start a ticket's thread, handed to `agentId` or else the workspace's lead */
export const startTicket = (ticket: number, agentId: number | null) =>
  write("POST", `/tickets/${ticket}/start`, agentId === null ? {} : { agent_id: agentId }, `starting ticket #${ticket}`, (r) => `started ticket #${ticket} as thread #${r.thread}`)
/** a coworker knob: a value, `inherit` (back to the archetype's) or `-` (leave it) */
export type Knob = string
const knobs = (model: Knob, effort: Knob, ask: Knob) =>
  Object.fromEntries(Object.entries({ model, effort, ask }).filter(([, v]) => v !== "-"))
export const hire = (ws: number, name: string, archetype: string, model: Knob, effort: Knob, ask: Knob) =>
  write("POST", `/workspaces/${ws}/coworkers`, { name, archetype, ...knobs(model, effort, ask) }, `hiring ${name}`, (c) => `hired ${c.name} (${c.archetype})`)
export const coworkerSet = (ws: number, agentId: number, model: Knob, effort: Knob, ask: Knob) =>
  write("PATCH", `/workspaces/${ws}/coworkers/${agentId}`, knobs(model, effort, ask), "retargeting a coworker", () => `retargeted coworker #${agentId}`)
/**
 * Ask a coworker one thing outside any thread (its own harness, read-only): the server says what
 * to run and where, and it runs HERE, so a model call never blocks the server. null when it failed.
 */
export async function aside(ws: number, agentId: number, question: string): Promise<string | null> {
  try {
    const spec: { argv: string[]; cwd: string | null } = await call("POST", `/workspaces/${ws}/coworkers/${agentId}/aside`, { question })
    const cwd = (spec.cwd ?? "~").replace(/^~/, GLib.get_home_dir())
    return (await execAsync(["sh", "-c", 'cd "$1" 2>/dev/null || cd; shift; exec timeout 180 "$@" </dev/null', "sh", cwd, ...spec.argv])).trim()
  } catch (e) {
    logEvent("agent", `aside failed: ${String(e)}`, "warn")
    return null
  }
}
export const workspaceNew = (name: string, repo: string) =>
  write("POST", "/workspaces", { name, ...(repo ? { repo } : {}) }, `making workspace ${name}`, (w) => `workspace #${w.id} ${w.name}`)
export const fire = (seatId: number, name: string) => write("DELETE", `/seats/${seatId}`, {}, `letting ${name} go`, () => `let ${name} go`)
export const ticketSet = (id: number, field: "status" | "title" | "body", value: string) =>
  write("PATCH", `/tickets/${id}`, { [field]: value }, `changing ticket #${id}`, () => `ticket #${id} ${field} set`)
/** send a ticket to the workspace's manager to staff (no manager: its lead starts it) */
export const ticketRoute = (id: number) =>
  write("POST", `/tickets/${id}/route`, {}, `sending ticket #${id} to the manager`, (r) => (r.routed_to ? `ticket #${id} sent to ${r.routed_to}` : `no manager: ticket #${id} started as thread #${r.thread}`))
/** close a thread as done: its sessions end, its ticket is done, a child reports up */
export const closeThread = (id: number) => write("POST", `/threads/${id}/close`, {}, `closing #${id}`, (t) => `closed #${id} — ${t.title}`)
export const ticketDelete = (id: number) => write("DELETE", `/tickets/${id}`, {}, `deleting ticket #${id}`, () => `deleted ticket #${id}`)
export const workspaceDelete = (id: number) => write("DELETE", `/workspaces/${id}`, {}, `deleting workspace #${id}`, () => `deleted workspace #${id}`)
/** start a workspace's other shift (Server.Shifts): the night crew on, or the day crew back */
export const shiftSwitch = (ws: number, shift: "day" | "night") =>
  write("POST", "/office/shift", { workspace_id: ws, shift }, `starting the ${shift} shift`, () => `the ${shift} shift is on`)
/** give a running thread to another coworker; staffed within seconds */
export const handOff = (tid: number, agent: string) => write("POST", `/threads/${tid}/hand-off`, { agent }, `handing #${tid} to ${agent}`, () => `handed #${tid} to ${agent}`)

// an alert's Open takes you to its thread in the office; the office registers how
let opener: (tid: number) => void = () => {}
export const setOpener = (fn: (tid: number) => void) => { opener = fn }
export const openInOffice = (tid: number) => opener(tid)

// the always-up service's operator API (loopback; its port is the service's, as flake.nix sets it)
const API = "http://127.0.0.1:4040/api"

// the command log gets the changes, not the polls: who woke, who slept, who waits on you
let last: Agents | null = null
function diff(next: Agents) {
  if (last?.ok) {
    const warm = new Map(last.roster.map((r) => [r.agent, r.warm]))
    for (const r of next.roster) {
      const was = warm.get(r.agent)
      if (was === undefined) logEvent("agent", `${r.agent} joined · ${r.title}`)
      else if (was !== r.warm) logEvent("agent", `${r.agent} ${r.warm ? "woke" : "went cold"}`, r.warm ? "normal" : "dim")
    }
    for (const r of last.roster) if (!next.roster.some((x) => x.agent === r.agent)) logEvent("agent", `${r.agent} left`, "dim")
    if (next.awaiting !== last.awaiting) logEvent("agent", next.awaiting ? `${next.awaiting} awaiting you` : "nothing awaits you", next.awaiting ? "warn" : "dim")
    // what waits on you is raised by the alerts (lib/alerts.ts: a decision banner), not a toast here
  } else if (last && !last.ok) logEvent("agent", "channel up")
  last = next
}

const EMPTY: Agents = { ok: false, roster: [], threads: [], counts: {}, awaiting: 0, bench: [], projects: [], tickets: [], workspaces: [], archetypes: [], models: [], notes: [], visits: [], triage: {}, health: null, calendar: {} }
export const [agents, setAgents] = createState<Agents>({ ...EMPTY, note: "…" })
export async function refreshAgents() {
  let next: Agents
  try {
    const res = await fetch(`${API}/office`)
    if (res.status !== 200) throw new Error(`office ${res.status}`)
    const j: any = await res.json()
    next = {
      ok: true, roster: j.roster ?? [], threads: j.threads ?? [], counts: j.counts ?? {}, awaiting: j.awaiting ?? 0,
      bench: j.bench ?? [], projects: j.projects ?? [], tickets: j.tickets ?? [], workspaces: j.workspaces ?? [], shifts: j.shifts ?? [], archetypes: j.archetypes ?? [], models: j.models ?? [], notes: j.notes ?? [], visits: j.visits ?? [], triage: j.triage ?? {}, health: j.health ?? null, calendar: j.calendar ?? {},
    }
  } catch {
    if (last?.ok) logEvent("agent", "channel down", "warn")
    last = { ...EMPTY, note: "channel down" }
    setAgents(last)
    return
  }
  // outside the try: a surface that throws on the new data is its own bug, not a channel down
  diff(next)
  setAgents(next)
}
refreshAgents()
interval(30_000, refreshAgents)
