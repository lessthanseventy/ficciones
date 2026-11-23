// babylon's board ($XDG_RUNTIME_DIR/babylon/board.json, rewritten within a second of a change),
// read again whenever the file changes.
import { createComputed, createState } from "ags"
import Gio from "gi://Gio?version=2.0"
import GLib from "gi://GLib?version=2.0"
import { parse, asking, type Board } from "./board-core"
import { sessions } from "./sessions"
import { waiting } from "./sessions-core"

const FILE = `${GLib.get_user_runtime_dir()}/babylon/board.json`

export const [board, setBoard] = createState<Board | null>(null)

function refresh() {
  try {
    const [ok, bytes] = GLib.file_get_contents(FILE)
    setBoard(ok ? parse(new TextDecoder().decode(bytes)) : null)
  } catch { setBoard(null) }
}

const monitor = Gio.File.new_for_path(FILE).monitor_file(Gio.FileMonitorFlags.NONE, null)
// pinned: no closure holds it once the module has run, and a collected monitor goes silent
;(globalThis as { boardMonitor?: Gio.FileMonitor }).boardMonitor = monitor
let pending = 0
monitor.connect("changed", () => {
  if (pending) return
  pending = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 150, () => { pending = 0; refresh(); return GLib.SOURCE_REMOVE })
})
refresh()

/** what waits on you, in words: the open asks, then the sessions waiting on an answer */
export const waitingOnYou = createComputed(() => waiting(sessions(), asking(board())))
