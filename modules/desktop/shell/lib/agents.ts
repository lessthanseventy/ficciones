// The Tlön roster + thread counts for the AGENTS pane and the office, via scripts/tlon-cli.sh
// shell-status (an rpc into the always-up server node). Polled every 30 s, and at once after a
// write (`refreshAgents`); "channel down" when the server is not up.
import { createState } from "ags"
import { interval } from "ags/time"
import { execAsync } from "ags/process"
import { logEvent } from "./log"

/** `prompt`: its coworker is sitting on a dialog (Server.Attention) — the ask, answered from the thread */
export type Thread = { id: number; title: string; stage: string | null; awaiting: string | null; workspace_id?: number | null; prompt?: { summary: string; options?: { key: string; label: string }[] | null } | null }
/** `archetype`/`lead`: the agent's seat on its workspace bench (null/false off every bench) */
export type Seat = { agent: string; thread_id: number; title: string; warm: boolean; archetype?: string | null; lead?: boolean; workspace_id?: number | null }
/** a model as the server names it; `thinking` is the effort level */
export type ModelSpec = { provider: string; model: string; thinking: string }
/** a coworker a workspace employs, on a thread or not; `model`/`ask` are its policy, null = the archetype's */
export type Coworker = { workspace_id: number; agent_id: number; name: string; archetype: string | null; lead: boolean; model: ModelSpec | null; ask: string | null }
/** what an archetype is beyond its prompt: `meta` never works a thread, `read_only` cannot write */
export type Archetype = { name: string; meta: boolean; read_only: boolean; model: string }
/** a model a coworker may run, keyed `provider/model`, with the harness it resolves to here */
export type ModelChoice = ModelSpec & { key: string; harness: string }
/** a filed ticket nobody has started yet */
export type Ticket = { id: number; workspace_id: number; project_id: number | null; title: string; priority: string }
export type Agents = {
  ok: boolean
  roster: Seat[]
  /** every open thread, newest first — the pane's rows; a staffed one carries its roster entry */
  threads: Thread[]
  counts: Record<string, number>
  awaiting: number
  bench: Coworker[]
  projects: { id: number; workspace_id: number; name: string }[]
  tickets: Ticket[]
  workspaces: { id: number; name: string }[]
  archetypes: Archetype[]
  models: ModelChoice[]
  note?: string
}
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
export const workspaceNew = (name: string, repo: string) => write(["workspace-new", name, ...(repo ? [repo] : [])], `making workspace ${name}`)

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
      execAsync(["notify-send", "-a", "tlön", "-u", "normal", "tlön needs you", `${next.awaiting} thread${next.awaiting === 1 ? "" : "s"} awaiting you`]).catch(() => void 0)
    // a coworker stuck on a permission dialog names what it is asking about, so the toast is the ask
    const asked = new Set(last.threads.filter((t) => t.prompt).map((t) => t.id))
    for (const t of next.threads)
      if (t.prompt && !asked.has(t.id))
        execAsync(["notify-send", "-a", "tlön", "-u", "normal", `#${t.id} ${t.title} is waiting on you`, t.prompt.summary]).catch(() => void 0)
  } else if (last && !last.ok) logEvent("agent", "channel up")
  last = next
}

const EMPTY: Agents = { ok: false, roster: [], threads: [], counts: {}, awaiting: 0, bench: [], projects: [], tickets: [], workspaces: [], archetypes: [], models: [] }
export const [agents, setAgents] = createState<Agents>({ ...EMPTY, note: "…" })
export async function refreshAgents() {
  try {
    const out = await execAsync([CLI, "shell-status"])
    const j = JSON.parse(out.trim().split("\n").pop() ?? "{}")
    const next: Agents = {
      ok: true, roster: j.roster ?? [], threads: j.threads ?? [], counts: j.counts ?? {}, awaiting: j.awaiting ?? 0,
      bench: j.bench ?? [], projects: j.projects ?? [], tickets: j.tickets ?? [], workspaces: j.workspaces ?? [], archetypes: j.archetypes ?? [], models: j.models ?? [],
    }
    diff(next)
    setAgents(next)
  } catch {
    if (last?.ok) logEvent("agent", "channel down", "warn")
    last = { ...EMPTY, note: "channel down" }
    setAgents(last)
  }
}
refreshAgents()
interval(30_000, refreshAgents)
