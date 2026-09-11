// One brightness value, two backends. Laptop alone: the backlight. An external monitor plugged
// in (no DDC/CI through the dock): hyprsunset's gamma, 30–100 %, software and global — the
// honest fake. Shared by the POWER popover's slider and the wheel over the battery cell.
import Brightness from "gi://AstalBrightness"
import { createBinding, createComputed, type Accessor } from "ags"
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import { hypr } from "./hypr"

const dev = Brightness.get_default()?.screen
export const external: Accessor<boolean> = createBinding(hypr, "monitors")((ms) => ms.some((m) => m.name !== "eDP-1"))
export const gamma = createPoll(1, 3000, async () => {
  try { return Math.max(0.3, Math.min(1, Number((await execAsync(["hyprctl", "hyprsunset", "gamma"])).trim()) / 100)) } catch { return 1 }
})
const back = dev ? createBinding(dev, "brightness")((x) => (Number.isFinite(x) && x >= 0 ? x : 0)) : null
export const brightness: Accessor<number> = createComputed(() => (external() || !back ? gamma() : back()))
export const usingGamma = () => external.peek() || !dev
export const floor = () => (usingGamma() ? 0.3 : 0)

let onGamma: ((v: number) => void) | null = null
/** The OSD hooks in here: gamma has no property to watch. */
export const onGammaChange = (f: (v: number) => void) => { onGamma = f }

export function setBrightness(v: number) {
  v = Math.max(floor(), Math.min(1, v))
  if (usingGamma()) {
    if (Math.abs(v - gamma.peek()) > 0.005) {
      execAsync(["hyprctl", "hyprsunset", "gamma", String(Math.round(v * 100))]).catch(console.error)
      onGamma?.(v)
    }
  } else if (dev && Math.abs(v - dev.brightness) > 0.005) dev.brightness = v
}
export const stepBrightness = (delta: number) => setBrightness(brightness.peek() + delta)
