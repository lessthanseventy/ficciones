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

// The file is over a megabyte and parsed on the main thread, so a change event that leaves it as
// it was (one write raises several) costs a stat, not a parse.
let seen = ""
function refresh() {
  try {
    const info = Gio.File.new_for_path(FILE).query_info("time::modified,time::modified-usec,standard::size", Gio.FileQueryInfoFlags.NONE, null)
    const stamp = `${info.get_attribute_uint64("time::modified")}.${info.get_attribute_uint32("time::modified-usec")}:${info.get_size()}`
    if (stamp === seen) return
    seen = stamp
    const [ok, bytes] = GLib.file_get_contents(FILE)
    setBoard(ok ? parse(new TextDecoder().decode(bytes)) : null)
  } catch { seen = ""; setBoard(null) }
}

const monitor = Gio.File.new_for_path(FILE).monitor_file(Gio.FileMonitorFlags.NONE, null)
// pinned: no closure holds it once the module has run, and a collected monitor goes silent
;(globalThis as { boardMonitor?: Gio.FileMonitor }).boardMonitor = monitor
let pending = 0
monitor.connect("changed", () => {
  if (pending) return
  // at most one read a second: babylon rewrites it on every change, many a second while it churns
  pending = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => { pending = 0; refresh(); return GLib.SOURCE_REMOVE })
})
refresh()

/** what waits on you, in words: the open asks, then the sessions waiting on an answer */
export const waitingOnYou = createComputed(() => waiting(sessions(), asking(board())))
