// The keyboard's state for the bar's glyphs: caps lock and the active layout, from
// `hyprctl devices` (Hyprland has no event for caps; the poll is small), only shown when
// notable — caps on, or a layout other than the first.
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"

export type Kbd = { caps: boolean; layout: string }
export const kbd = createPoll<Kbd>({ caps: false, layout: "" }, 2000, async () => {
  try {
    const j = JSON.parse(await execAsync(["hyprctl", "devices", "-j"]))
    const k = (j.keyboards as any[]).find((x) => x.main) ?? j.keyboards?.[0]
    return { caps: !!k?.capsLock, layout: String(k?.active_keymap ?? "") }
  } catch { return { caps: false, layout: "" } }
})
/** "English (US)" → "us"; "Deutsch" → "de" — the short form for a cell */
export const layoutShort = (l: string) => {
  const m = l.match(/\(([A-Za-z]{2,3})\)/)
  return (m ? m[1] : l.slice(0, 2)).toLowerCase()
}
