// Glass: window transparency. With it on, terminals (ghostty) are always glass; every other window
// is glass too until a video plays anywhere (lib/opaque.ts says so), then they all go opaque until
// it stops. tlon's office is never glass (a window rule in hyprland.lua). Off, everything is
// opaque. The toggle is kept in the state dir; hyprland.lua starts glass on, which is the default.
import { createState } from "ags"
import GLib from "gi://GLib?version=2.0"
import { keyword } from "./hyprlua"

const STATE = `${GLib.get_user_state_dir()}/astal-shell/glass`
// one value for both: background windows are not dimmer than the foreground (Andrew, 2026-09-08)
export const GLASS = "0.90"

function load(): boolean {
  try {
    const [ok, bytes] = GLib.file_get_contents(STATE)
    if (ok) return new TextDecoder().decode(bytes).trim() !== "off"
  } catch { /* never toggled */ }
  return true
}

export const [glass, setGlassState] = createState(load())
/** a video is playing somewhere (lib/opaque.ts) */
export const [videoPlaying, setVideoPlaying] = createState(false)

function apply() {
  const v = glass.peek() && !videoPlaying.peek() ? GLASS : "1.0"
  Promise.all([keyword("decoration:active_opacity", v), keyword("decoration:inactive_opacity", v)]).catch(console.error)
}
videoPlaying.subscribe(apply)
apply()

export function setGlass(on: boolean) {
  setGlassState(on)
  try {
    GLib.mkdir_with_parents(GLib.path_get_dirname(STATE), 0o755)
    GLib.file_set_contents(STATE, on ? "on" : "off")
  } catch (e) { console.error("glass:", String(e)) }
  apply()
}
export const toggleGlass = () => setGlass(!glass.peek())
