// Desktop notices for board.json's needs_you (lib/needs-core.ts): one per item id, taken back when
// the id leaves, none while arena's window is the one in focus. Their actions run the item's argv.
import Gio from "gi://Gio?version=2.0"
import GLib from "gi://GLib?version=2.0"
import Notifd from "gi://AstalNotifd"
import { board } from "./board"
import { hypr } from "./hypr"
import { logEvent } from "./log"
import { goToArena } from "./sessions"
import { findArena, itemArgs } from "./sessions-core"
import { HINT, chosen, noticeArgv, parseRaised, plan } from "./needs-core"
import type { Item } from "./board-core"

const notifd = Notifd.get_default()
const STATE = `${GLib.get_user_state_dir()}/astal-shell/needs-raised.json`

function load(): string[] {
  try {
    const [ok, bytes] = GLib.file_get_contents(STATE)
    return ok ? parseRaised(new TextDecoder().decode(bytes)) : []
  } catch { return [] }
}

function save() {
  try {
    GLib.mkdir_with_parents(GLib.path_get_dirname(STATE), 0o755)
    GLib.file_set_contents(STATE, JSON.stringify([...raised.keys()]))
  } catch (e) { logEvent("agent", `needs state: ${String(e)}`, "warn") }
}

// Ids raised before a restart stay raised: the notices died with the old shell, but they were seen.
const raised = new Map<string, Gio.Subprocess | null>(load().map((id) => [id, null]))

const inFront = () => {
  const f = hypr.focusedClient
  return !!f && findArena([f]) !== undefined
}

function close(id: string) {
  raised.get(id)?.force_exit()
  raised.delete(id)
  for (const n of notifd.notifications) if (n.get_hint(HINT)?.get_string()[0] === id) n.dismiss()
}

function raise(i: Item, n: number, socket: string | null) {
  let p: Gio.Subprocess
  try {
    p = Gio.Subprocess.new(noticeArgv(i, n), Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE)
  } catch (e) { return logEvent("agent", `notify-send: ${String(e)}`, "warn") }
  raised.set(i.id, p)
  p.communicate_utf8_async(null, null, (_, r) => {
    let out = ""
    try { out = p.communicate_utf8_finish(r)[1] ?? "" } catch { return }
    if (raised.get(i.id) !== p) return
    const argv = chosen(i, out)
    if (argv) run(argv)
    else if (out.trim() === "default") goToArena(itemArgs(i.ticket, socket))
  })
}

function run(argv: string[]) {
  try {
    const p = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDERR_SILENCE)
    p.wait_async(null, (_, r) => {
      try { p.wait_finish(r) } catch { /* reported below */ }
      if (!p.get_successful()) logEvent("agent", `${argv.join(" ")} exited ${p.get_exit_status()}`, "warn")
    })
  } catch (e) { logEvent("agent", `${argv.join(" ")}: ${String(e)}`, "warn") }
}

function follow() {
  const b = board.peek()
  if (!b) return
  const p = plan(new Set(raised.keys()), b.needsYou, inFront())
  for (const id of p.close) close(id)
  for (const id of p.seen) raised.set(id, null)
  for (const i of p.raise) raise(i, b.needsYou.length, b.socket)
  if (p.close.length || p.seen.length) save()
}

board.subscribe(follow)
follow()
