// Every Claude Code session on the machine, from the records its hook keeps in
// $XDG_RUNTIME_DIR/sessions (arena's plugin): read again whenever the directory
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
import { toArena as toArenaWith, type Shell } from "./arena-go"
import { parse, metered, alive, chimes, inboxArgs, findArena, type Session } from "./sessions-core"

export type { Session }

const DIR = `${GLib.get_user_runtime_dir()}/sessions`
const ARENA = "com.ghostty.arena"

export const [sessions, setSessions] = createState<Session[]>([])

function text(path: string): string | null {
  try {
    const [ok, bytes] = GLib.file_get_contents(path)
    return ok ? new TextDecoder().decode(bytes) : null
  } catch { return null }
}

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
      if (s) out.push(metered(s, text(`${DIR}/${s.id}.meter`)))
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
let again = false
async function refresh() {
  // a record written while this reads is read after it, not a minute later
  if (reading) { again = true; return }
  reading = true
  try {
    const all = records()
    const live = await livePanes(all)
    const at = Date.now() / 1000
    const now = all.filter((s) => alive(s, live, at, (cwd) => GLib.file_test(cwd, GLib.FileTest.IS_DIR)))
    const before = new Map(sessions.peek().map((s) => [s.id, s]))
    for (const sfx of new Set(chimes(before, now, at))) play(sfx)
    setSessions(now)
  } finally {
    reading = false
    if (again) { again = false; void refresh() }
  }
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

const arenaWindow = () => findArena(hypr.get_clients())
const focusArena = (address: string) => dispatchNow(L.focusWindow(`address:0x${address.replace(/^0x/, "")}`))
function openArena(...args: string[]) {
  const cmd = ["ghostty", "--title=arena", `--class=${ARENA}`, "-e", "arena", ...args]
  dispatchNow(`hl.dsp.exec_cmd(${JSON.stringify(cmd.map((a) => `'${a.replace(/'/g, "'\\''")}'`).join(" "))})`)
}

const run = (argv: string[]) =>
  new Promise<number>((resolve, reject) => {
    try {
      const p = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDERR_SILENCE)
      p.wait_async(null, (_, r) => { try { p.wait_finish(r); resolve(p.get_exit_status()) } catch (e) { reject(e) } })
    } catch (e) { reject(e) }
  })

function notice(text: string) {
  execAsync(["notify-send", "-a", "arena", "arena", text]).catch(() => {})
}

const shell: Shell = {
  run,
  open: () => {},
  notify: notice,
  log: (t) => logEvent("agent", t, "warn"),
  arena: arenaWindow,
  focus: focusArena,
}

/** The one way the shell sends you somewhere: arena's window focused, then arena told `args`; `open` starts one when none is running. */
const toArena = (args: string[], open: () => void) => toArenaWith(args, open, shell)

/** Put arena in front of you with `args` (arena board N, arena inbox). */
export const goToArena = (args: string[]) => void toArena(args, () => openArena(...args))

/** Put arena in front of you with its inbox (Your move) open. `socket` is the board's tmux server. */
export const goToInbox = (socket: string | null) => goToArena(inboxArgs(socket))

void refresh()
