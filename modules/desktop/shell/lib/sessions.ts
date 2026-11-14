// Every Claude Code session on the machine, from the records its hook keeps in
// $XDG_RUNTIME_DIR/sessions (modules/agents/session-state.sh): read again whenever the directory
// changes, and once a minute so the times move on and a crashed session's record drops off.
import { createState } from "ags"
import { interval } from "ags/time"
import { execAsync } from "ags/process"
import Gio from "gi://Gio?version=2.0"
import GLib from "gi://GLib?version=2.0"
import { play } from "./sfx"
import { dispatchNow, L } from "./hyprlua"
import { hypr } from "./hypr"
import { logEvent } from "./log"
import { parse, alive, chimes, arenaTarget, type Session } from "./sessions-core"

export type { Session }
export { mine, tally, mark, nextUp, line, isCrew } from "./sessions-core"

const DIR = `${GLib.get_user_runtime_dir()}/sessions`
const ARENA = "com.ghostty.arena"

export const [sessions, setSessions] = createState<Session[]>([])
/** when the records were last read: the rows' times follow it */
export const [readAt, setReadAt] = createState(Date.now() / 1000)

function records(): Session[] {
  const out: Session[] = []
  const dir = Gio.File.new_for_path(DIR)
  let it: Gio.FileEnumerator
  try { it = dir.enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, null) } catch { return out }
  for (let info = it.next_file(null); info; info = it.next_file(null)) {
    const name = info.get_name()
    if (name.startsWith(".") || !name.endsWith(".json")) continue
    try {
      const [ok, bytes] = GLib.file_get_contents(`${DIR}/${name}`)
      const s = ok ? parse(new TextDecoder().decode(bytes)) : null
      if (s) out.push(s)
    } catch { /* written away under us */ }
  }
  return out
}

async function livePanes(all: Session[]): Promise<Set<string>> {
  const live = new Set<string>()
  for (const socket of new Set(all.map((s) => s.socket).filter(Boolean))) {
    try {
      const out = await execAsync(["tmux", "-S", socket, "list-panes", "-a", "-F", "#{pane_id}"])
      for (const p of out.split("\n")) if (p) live.add(`${socket} ${p}`)
    } catch { /* that server is gone, and every pane on it */ }
  }
  return live
}

let reading = false
async function refresh() {
  if (reading) return
  reading = true
  try {
    const all = records()
    const live = await livePanes(all)
    const now = all.filter((s) => alive(s, live))
    const before = new Map(sessions.peek().map((s) => [s.id, s]))
    for (const sfx of new Set(chimes(before, now, Date.now() / 1000))) play(sfx)
    setSessions(now)
    setReadAt(Date.now() / 1000)
  } finally { reading = false }
}

try { GLib.mkdir_with_parents(DIR, 0o700) } catch { /* the hook makes it too */ }
const monitor = Gio.File.new_for_path(DIR).monitor_directory(Gio.FileMonitorFlags.NONE, null)
// pinned: no closure holds it once the module has run, and a collected monitor goes silent
;(globalThis as { sessionsMonitor?: Gio.FileMonitor }).sessionsMonitor = monitor
let pending = 0
monitor.connect("changed", () => {
  // a hook writes a temp file and renames it over the record: one read for the burst
  if (pending) return
  pending = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => { pending = 0; void refresh(); return GLib.SOURCE_REMOVE })
})
interval(60_000, () => void refresh())

/** Put `s` in front of you: arena's window focused on its pane, arena opened on it if none is up. */
export async function goTo(s: Session) {
  if (!s.pane) return logEvent("agent", `${s.repo}: not in tmux, nowhere to go`, "warn")
  const tmux = (...a: string[]) => execAsync(["tmux", "-S", s.socket, ...a])
  try {
    await tmux("select-window", "-t", s.pane)
    await tmux("select-pane", "-t", s.pane)
    const arena = hypr.get_clients().find((c) => c.class === ARENA)
    if (arena) {
      dispatchNow(L.focusWindow(`address:0x${arena.address.replace(/^0x/, "")}`))
      const clients = await tmux("list-clients", "-F", "#{client_control_mode} #{client_name}")
      for (const c of clients.split("\n")) if (c.startsWith("1 ")) await tmux("switch-client", "-c", c.slice(2), "-t", s.pane)
    } else {
      const session = (await tmux("display-message", "-p", "-t", s.pane, "#{session_name}")).trim()
      const cmd = ["ghostty", "--title=arena", `--class=${ARENA}`, "-e", "arena", ...arenaTarget(s), session]
      dispatchNow(`hl.dsp.exec_cmd(${JSON.stringify(cmd.map((a) => `'${a.replace(/'/g, "'\\''")}'`).join(" "))})`)
    }
  } catch (e) { logEvent("agent", `go to ${s.repo}: ${String(e)}`, "warn") }
}

void refresh()
