// The Tlön roster + thread counts for the AGENTS pane and the office, via scripts/tlon-cli.sh
// shell-status (an rpc into the always-up server node). Polled every 30 s, and at once after a
// write (`refreshAgents`); "channel down" when the server is not up.
import { createState } from "ags"
import { interval } from "ags/time"
import { execAsync } from "ags/process"
import { logEvent } from "./log"

// the snapshot's shape is tlon's (office/kit/types.ts, the shell-status contract), shared with
// every office surface
import type { Agents, ThreadView } from "../office/kit/types"
export type { Agents, Archetype, Coworker, ModelChoice, ModelSpec, Note, Seat, Thread, ThreadView, Ticket, Visit } from "../office/kit/types"
/** a thread's brief, the scope get_dossier hands an agent (scripts/tlon-cli.sh shell-dossier) */
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
    const out = await execAsync([CLI, "shell-dossier", String(id)])
    return JSON.parse(out.trim().split("\n").pop() ?? "null")
  } catch { return null }
}
export async function threadView(id: number): Promise<ThreadView | null> {
  try {
    const out = await execAsync([CLI, "shell-thread", String(id)])
    return JSON.parse(out.trim().split("\n").pop() ?? "null")
  } catch { return null }
}
/** Post to a thread as the operator. A body naming an open prompt's option answers it. */
export async function post(id: number, body: string): Promise<boolean> {
  try {
    await execAsync([CLI, "post", String(id), body])
    logEvent("agent", `you → #${id}: ${body}`)
    return true
  } catch (e) {
    logEvent("agent", `post to #${id} failed: ${String(e)}`, "warn")
    return false
  }
}

async function write(args: string[], what: string): Promise<boolean> {
  try {
    const out = await execAsync([CLI, ...args])
    logEvent("agent", out.trim().split("\n").pop() ?? what)
    await refreshAgents()
    return true
  } catch (e) {
    logEvent("agent", `${what} failed: ${String(e)}`, "warn")
    return false
  }
}
export const fileTicket = (ws: number, project: number | null, title: string, body: string) =>
  write(["ticket-file", String(ws), project === null ? "-" : String(project), title, body], "filing a ticket")
/** start a ticket's thread, handed to `agentId` or else the workspace's lead */
export const startTicket = (ticket: number, agentId: number | null) =>
  write(["ticket-start", String(ticket), ...(agentId === null ? [] : [String(agentId)])], `starting ticket #${ticket}`)
/** a knob as the CLI takes it: a value, `inherit` (back to the archetype's) or `-` (leave it) */
export type Knob = string
export const hire = (ws: number, name: string, archetype: string, model: Knob, effort: Knob, ask: Knob) =>
  write(["hire", String(ws), name, archetype, model, effort, ask], `hiring ${name}`)
export const coworkerSet = (ws: number, agentId: number, model: Knob, effort: Knob, ask: Knob) =>
  write(["coworker-set", String(ws), String(agentId), model, effort, ask], "retargeting a coworker")
/** ask a coworker one thing outside any thread (its own harness, read-only); null when it failed */
export async function aside(ws: number, agentId: number, question: string): Promise<string | null> {
  try {
    return (await execAsync([CLI, "aside", String(ws), String(agentId), question])).trim()
  } catch (e) {
    logEvent("agent", `aside failed: ${String(e)}`, "warn")
    return null
  }
}
export const workspaceNew = (name: string, repo: string) => write(["workspace-new", name, ...(repo ? [repo] : [])], `making workspace ${name}`)
export const fire = (seatId: number, name: string) => write(["fire", String(seatId)], `letting ${name} go`)
export const ticketSet = (id: number, field: "status" | "title" | "body", value: string) => write(["ticket-set", String(id), field, value], `changing ticket #${id}`)
/** send a ticket to the workspace's manager to staff (no manager: its lead starts it) */
export const ticketRoute = (id: number) => write(["ticket-route", String(id)], `sending ticket #${id} to the manager`)
/** close a thread as done: its sessions end, its ticket is done, a child reports up */
export const closeThread = (id: number) => write(["close-thread", String(id)], `closing #${id}`)
export const ticketDelete = (id: number) => write(["ticket-delete", String(id)], `deleting ticket #${id}`)
export const workspaceDelete = (id: number) => write(["workspace-delete", String(id)], `deleting workspace #${id}`)
/** give a running thread to another coworker; staffed within seconds */
export const handOff = (tid: number, agent: string) => write(["hand-off", String(tid), agent], `handing #${tid} to ${agent}`)

// a click on a "waiting on you" toast opens the office there; the office registers how
let opener: (tid: number) => void = () => {}
export const setOpener = (fn: (tid: number) => void) => { opener = fn }
/** a toast whose click (freedesktop's default action) opens thread `tid`; notify-send waits for it */
const toast = (summary: string, body: string, tid: number | undefined) =>
  execAsync(["notify-send", "-a", "tlön", "-u", "normal", "-A", "default=open", summary, body])
    .then((out) => { if (out.trim() === "default" && tid !== undefined) opener(tid) })
    .catch(() => void 0)

// Single-user machine, fixed checkout — the same assumption flake.nix makes.
const CLI = "/home/andrew/projects/tlon/scripts/tlon-cli.sh"

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
    // the needs-you signal OUTSIDE any window (field baseline: every platform has one): a toast
    // through our own notifd when more threads wait on the operator than before
    if (next.awaiting > last.awaiting)
      toast("tlön needs you", `${next.awaiting} thread${next.awaiting === 1 ? "" : "s"} awaiting you`, next.threads.find((t) => t.awaiting || t.prompt)?.id)
    // a coworker stuck on a permission dialog names what it is asking about, so the toast is the ask
    const asked = new Set(last.threads.filter((t) => t.prompt).map((t) => t.id))
    for (const t of next.threads)
      if (t.prompt && !asked.has(t.id))
        toast(`#${t.id} ${t.title} is waiting on you`, t.prompt.summary, t.id)
  } else if (last && !last.ok) logEvent("agent", "channel up")
  last = next
}

const EMPTY: Agents = { ok: false, roster: [], threads: [], counts: {}, awaiting: 0, bench: [], projects: [], tickets: [], workspaces: [], archetypes: [], models: [], notes: [], visits: [] }
export const [agents, setAgents] = createState<Agents>({ ...EMPTY, note: "…" })
export async function refreshAgents() {
  let next: Agents
  try {
    const out = await execAsync([CLI, "shell-status"])
    const j = JSON.parse(out.trim().split("\n").pop() ?? "{}")
    next = {
      ok: true, roster: j.roster ?? [], threads: j.threads ?? [], counts: j.counts ?? {}, awaiting: j.awaiting ?? 0,
      bench: j.bench ?? [], projects: j.projects ?? [], tickets: j.tickets ?? [], workspaces: j.workspaces ?? [], archetypes: j.archetypes ?? [], models: j.models ?? [], notes: j.notes ?? [], visits: j.visits ?? [],
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
