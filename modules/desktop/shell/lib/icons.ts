// A window's icon, by its class: the desktop entry's icon, or the generic executable.
import Apps from "gi://AstalApps"
import type Hyprland from "gi://AstalHyprland"

const apps = new Apps.Apps()
export function iconFor(c: Hyprland.Client): string {
  const q = apps.exact_query(c.class)[0] ?? apps.fuzzy_query(c.class)[0]
  return q?.iconName ?? "application-x-executable"
}

/** The speaker glyph for a volume: mute, off (0), no wave (<20%), one wave (<60%), two. */
export function volumeGlyph(v: number, muted = false): string {
  if (muted) return "\u{f075f}"
  if (v <= 0.005) return "\u{f0581}"
  if (v < 0.2) return "\u{f057f}"
  if (v < 0.6) return "\u{f0580}"
  return "\u{f057e}"
}
