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
import { logEvent } from "./log"
import { setting, setSetting } from "./settings"

/** whether the inhibitor is HELD — not what was asked for: a refusal shows as off */
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

function hold(on: boolean) {
  if (on && !held) held = takeInhibitor()
  if (!on && held) {
    held.close(null)
    held = null
  }
  setAwakeState(!!held)
}
/** The wish is a setting (power.awake, remembered); the toggle shows what is held. */
export function toggleAwake() {
  const want = !awake.peek()
  // wanted already but refused: the click is a retry
  if (want === setting("power.awake").peek()) hold(want)
  else setSetting("power.awake", want)
}

/** At start: hold what the setting asks, and follow it from then on. */
export function initAwake() {
  // the state-dir file awake was kept in before it was a setting: an "off" in it carries over, once
  const old = `${GLib.get_user_state_dir()}/astal-shell/awake`
  try {
    const [ok, bytes] = GLib.file_get_contents(old)
    if (ok && new TextDecoder().decode(bytes).trim() === "off") setSetting("power.awake", false)
    GLib.unlink(old)
  } catch { /* no old file */ }
  hold(setting("power.awake").peek())
  setting("power.awake").subscribe(() => {
    const on = setting("power.awake").peek()
    hold(on)
    logEvent("shell", on ? (held ? "awake: idle inhibited" : "awake: wanted, but logind refused") : "awake off: idle may lock and suspend", "dim")
  })
}
