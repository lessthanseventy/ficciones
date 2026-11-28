// The keyboard's state for the bar's glyphs: caps lock and the active layout, only shown when
// notable — caps on, or a layout other than the first. Hyprland has no event for caps, so it is
// read from the keyboards' LEDs in sysfs (no process); the layout follows `activelayout`.
import { createPoll } from "./poll"
import { createComputed, createState } from "ags"
import { execAsync } from "ags/process"
import GLib from "gi://GLib?version=2.0"
import { hypr } from "./hypr"

const LEDS = "/sys/class/leds"
// the input numbers change when a keyboard is plugged in again, so the LEDs are listed each time
const capsOn = () => {
  try {
    const dir = GLib.Dir.open(LEDS, 0)
    for (let name = dir.read_name(); name !== null; name = dir.read_name()) {
      if (!name.endsWith("::capslock")) continue
      const [ok, bytes] = GLib.file_get_contents(`${LEDS}/${name}/brightness`)
      if (ok && new TextDecoder().decode(bytes).trim() !== "0") return true
    }
  } catch {}
  return false
}
const caps = createPoll(false, 2000, capsOn)

const [layout, setLayout] = createState("")
execAsync(["hyprctl", "devices", "-j"]).then((out) => {
  const keyboards = (JSON.parse(out).keyboards ?? []) as { main?: boolean; active_keymap?: string }[]
  const k = keyboards.find((x) => x.main) ?? keyboards[0]
  setLayout(String(k?.active_keymap ?? ""))
}).catch(() => {})
// `activelayout>>KEYBOARD,LAYOUT`: the layout's name is everything after the first comma
hypr.connect("event", (_, ev: string, data: string) => {
  if (ev === "activelayout") setLayout(data.slice(data.indexOf(",") + 1))
})

export type Kbd = { caps: boolean; layout: string }
export const kbd = createComputed(() => ({ caps: caps(), layout: layout() }))
/** "English (US)" → "us"; "Deutsch" → "de" — the short form for a cell */
export const layoutShort = (l: string) => {
  const m = l.match(/\(([A-Za-z]{2,3})\)/)
  return (m ? m[1] : l.slice(0, 2)).toLowerCase()
}
