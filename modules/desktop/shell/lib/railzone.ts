// The rail's exclusive zone, widened for the sidecar. The column beside the rail is held open
// by the rail itself: its zone becomes rail + column while a sidecar is pinned, and goes back
// to auto on unpin. No second layer window — every way of making one invisible (a transparent
// background, opacity, a css class with any rule) left GTK sizing it at 200px with a zero zone
// (bisected 2026-09-06), and an opaque one on BOTTOM is arranged before the rail.
import Astal from "gi://Astal?version=4.0"
import LayerShell from "gi://Gtk4LayerShell?version=1.0"

const rails = new Map<string, Astal.Window>()
const base = new Map<string, number>()

export function registerRail(connector: string, win: Astal.Window) { rails.set(connector, win) }

/** Reserve `extra` px beyond the rail on this monitor; 0 restores the rail's own zone. */
export function extendRail(connector: string, extra: number) {
  const w = rails.get(connector)
  if (!w) return
  if (!base.has(connector)) base.set(connector, Math.max(LayerShell.get_exclusive_zone(w), w.get_width()))
  if (extra > 0) LayerShell.set_exclusive_zone(w, base.get(connector)! + extra)
  else LayerShell.auto_exclusive_zone_enable(w)
}
