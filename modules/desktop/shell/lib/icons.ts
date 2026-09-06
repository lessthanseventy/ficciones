// A window's icon, by its class: the desktop entry's icon, or the generic executable.
import Apps from "gi://AstalApps"
import type Hyprland from "gi://AstalHyprland"

const apps = new Apps.Apps()
export function iconFor(c: Hyprland.Client): string {
  const q = apps.exact_query(c.class)[0] ?? apps.fuzzy_query(c.class)[0]
  return q?.iconName ?? "application-x-executable"
}
