// "Awake": an idle inhibitor the shell holds (systemd-inhibit --what=idle) so hypridle's chain
// — lock, screen off, suspend — does not fire. ON by default and remembered across restarts
// (Andrew, 2026-09-07: docked, the machine should stay up unless he says otherwise); the
// coffee cup in the bar shows it, the toggle in the hub and the dashboard flips it.
import GLib from "gi://GLib?version=2.0"
import { createState } from "ags"
import { subprocess, type Process } from "ags/process"
import { readFile, writeFile } from "ags/file"
import { logEvent } from "./log"

const STATE = `${GLib.get_user_state_dir()}/astal-shell/awake`
export const [awake, setAwakeState] = createState(false)
let proc: Process | null = null

export function setAwake(on: boolean, remember = true) {
  if (on && !proc) proc = subprocess(["systemd-inhibit", "--what=idle", "--who=astal-shell", "--why=awake", "sleep", "infinity"], () => {}, () => {})
  if (!on && proc) { proc.kill(); proc = null }
  setAwakeState(on)
  if (remember) {
    try { GLib.mkdir_with_parents(GLib.path_get_dirname(STATE), 0o755); writeFile(STATE, on ? "on" : "off") } catch { /* state dir */ }
    logEvent("shell", on ? "awake: idle inhibited" : "awake off: idle may lock and suspend", "dim")
  }
}
export const toggleAwake = () => setAwake(!awake.peek())

/** At start: what was remembered, on when nothing was. */
export function initAwake() {
  let on = true
  try { on = readFile(STATE).trim() !== "off" } catch { /* first run */ }
  setAwake(on, false)
}
