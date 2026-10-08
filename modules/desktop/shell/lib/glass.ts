// Glass: window transparency. With it on, terminals (ghostty) are always glass; every other window
// is glass too until a video plays anywhere (lib/opaque.ts says so), then they all go opaque until
// it stops. tlon's office is never glass (a window rule in hyprland.lua). Off, everything is
// opaque. On/off and the opacity are settings (look.glass, look.glassOpacity).
import { createState } from "ags"
import GLib from "gi://GLib?version=2.0"
import { keyword } from "./hyprlua"
import { setting, setSetting } from "./settings"

export const glass = setting("look.glass")
/** the glass opacity as Hyprland takes it */
export const glassOpacity = () => Math.min(1, Math.max(0.3, setting("look.glassOpacity").peek())).toFixed(2)
/** a video is playing somewhere (lib/opaque.ts) */
export const [videoPlaying, setVideoPlaying] = createState(false)

// the state-dir file glass was kept in before it was a setting: an "off" in it carries over, once
const OLD = `${GLib.get_user_state_dir()}/astal-shell/glass`
try {
  const [ok, bytes] = GLib.file_get_contents(OLD)
  if (ok && new TextDecoder().decode(bytes).trim() === "off") setSetting("look.glass", false)
  GLib.unlink(OLD)
} catch { /* no old file */ }

function apply() {
  const v = glass.peek() && !videoPlaying.peek() ? glassOpacity() : "1.0"
  Promise.all([keyword("decoration:active_opacity", v), keyword("decoration:inactive_opacity", v)]).catch(console.error)
}
videoPlaying.subscribe(apply)
glass.subscribe(apply)
setting("look.glassOpacity").subscribe(apply)
apply()

export const setGlass = (on: boolean) => setSetting("look.glass", on)
export const toggleGlass = () => setGlass(!glass.peek())
