// Global transparency: Hyprland's active/inactive window opacity, toggled as a pair.
import { createState } from "ags"
import { keyword } from "./hyprlua"

export const [glass, setGlassState] = createState(false)
const ON = ["0.88", "0.78"], OFF = ["1.0", "1.0"]

export function setGlass(on: boolean) {
  const [a, i] = on ? ON : OFF
  Promise.all([
    keyword("decoration:active_opacity", a),
    keyword("decoration:inactive_opacity", i),
  ]).then(() => setGlassState(on)).catch(console.error)
}
export const toggleGlass = () => setGlass(!glass.get())
