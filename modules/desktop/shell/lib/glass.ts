// Global transparency: Hyprland's active/inactive window opacity, toggled as a pair.
import { createState } from "ags"
import { execAsync } from "ags/process"
import { keyword } from "./hyprlua"

export const [glass, setGlassState] = createState(false)
// one value for both: background windows are not dimmer than the foreground (Andrew, 2026-09-08)
const ON = ["0.90", "0.90"], OFF = ["1.0", "1.0"]
// the toggle outlives the shell (Hyprland keeps the opacity across a shell restart): seed it
// from the live value or the Hub says off while the windows are glass (2026-09-08)
execAsync(["hyprctl", "getoption", "decoration:active_opacity", "-j"])
  .then((out) => setGlassState(Number(JSON.parse(out).float) < 1))
  .catch(() => {})

export function setGlass(on: boolean) {
  const [a, i] = on ? ON : OFF
  Promise.all([
    keyword("decoration:active_opacity", a),
    keyword("decoration:inactive_opacity", i),
  ]).then(() => setGlassState(on)).catch(console.error)
}
export const toggleGlass = () => setGlass(!glass.get())
