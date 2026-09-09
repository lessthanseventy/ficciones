// "Awake": an idle inhibitor the shell holds so hypridle's chain — lock, screen off, suspend —
// does not fire. ON by default and remembered across restarts (Andrew, 2026-09-07: docked, the
// machine should stay up unless he says otherwise); the coffee cup in the bar shows it, the
// toggle in the hub and the dashboard flips it.
//
// The lock is a logind FILE DESCRIPTOR, not a `systemd-inhibit` child: the kernel drops an fd when
// the holder dies, so a crashed shell releases its inhibitor. A child is reparented to init and
// holds the lock forever, where only `systemd-inhibit --list` would ever show it.
import Gio from "gi://Gio?version=2.0"
import GioUnix from "gi://GioUnix?version=2.0"
import GLib from "gi://GLib?version=2.0"
import { createState } from "ags"
import { readFile, writeFile } from "ags/file"
import { logEvent } from "./log"

const STATE = `${GLib.get_user_state_dir()}/astal-shell/awake`
export const [awake, setAwakeState] = createState(false)

// Wrapped rather than a raw fd so release is deterministic; GC would drop the lock whenever.
let held: GioUnix.InputStream | null = null

/** An `idle` block from logind, or null — a refusal must not throw into a toggle. */
function takeInhibitor(): GioUnix.InputStream | null {
  try {
    const [reply, fds] = Gio.DBus.system.call_with_unix_fd_list_sync(
      "org.freedesktop.login1",
      "/org/freedesktop/login1",
      "org.freedesktop.login1.Manager",
      "Inhibit",
      new GLib.Variant("(ssss)", ["idle", "astal-shell", "awake", "block"]),
      new GLib.VariantType("(h)"),
      Gio.DBusCallFlags.NONE,
      -1,
      null,
      null,
    )
    const index = reply.deepUnpack<[number]>()[0]
    if (!fds) throw new Error("no fd list in the Inhibit reply")
    // owns the fd: close() releases the lock, and nothing else can double-close it
    return GioUnix.InputStream.new(fds.steal_fds()[index], true)
  } catch (e) {
    logEvent("shell", `awake: logind refused the inhibitor — ${e}`, "warn")
    return null
  }
}

export function setAwake(on: boolean, remember = true) {
  if (on && !held) held = takeInhibitor()
  if (!on && held) {
    held.close(null)
    held = null
  }
  setAwakeState(on)
  if (remember) {
    try {
      GLib.mkdir_with_parents(GLib.path_get_dirname(STATE), 0o755)
      writeFile(STATE, on ? "on" : "off")
    } catch {
      /* state dir */
    }
    logEvent("shell", on ? "awake: idle inhibited" : "awake off: idle may lock and suspend", "dim")
  }
}
export const toggleAwake = () => setAwake(!awake.peek())

/** At start: what was remembered, on when nothing was. */
export function initAwake() {
  let on = true
  try {
    on = readFile(STATE).trim() !== "off"
  } catch {
    /* first run */
  }
  setAwake(on, false)
}
