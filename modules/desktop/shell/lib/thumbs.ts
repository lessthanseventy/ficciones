// Window thumbnails for the workspace strips: grim crops each mapped window on the workspace
// that just became visible (and the ones showing at start), scaled to a quarter, into the
// cache dir keyed by window address. A hidden workspace shows its windows as they last were —
// Wayland has no way to picture a window that is not on screen. `stamp` bumps after a capture
// so pictures reload.
import Gio from "gi://Gio?version=2.0"
import GLib from "gi://GLib?version=2.0"
import Hyprland from "gi://AstalHyprland"
import { createState } from "ags"
import { execAsync } from "ags/process"
import { timeout, type Timer } from "ags/time"
import { hypr } from "./hypr"

const DIR = `${GLib.get_user_cache_dir()}/astal-shell/thumbs`
GLib.mkdir_with_parents(DIR, 0o755)
export const pathFor = (address: string) => `${DIR}/${address.replace(/^0x/, "")}.jpg`
export const [stamp, setStamp] = createState(0)

type Rect = { x: number; y: number; w: number; h: number }
/** The captured rectangle per window — a scrolling layout leaves columns partly off screen. */
export const geom = new Map<string, Rect>()

/** Windows on a workspace that is on screen right now, clipped to the monitor, left to right. */
function visibleClients(ws: Hyprland.Workspace): { c: Hyprland.Client; r: Rect }[] {
  const m = hypr.get_monitors().find((mm) => mm.activeWorkspace?.id === ws.id)
  if (!m) return []
  return hypr.get_clients()
    .filter((c) => c.workspace?.id === ws.id && c.mapped)
    .map((c) => {
      const x0 = Math.max(c.x, m.x), y0 = Math.max(c.y, m.y)
      const x1 = Math.min(c.x + c.width, m.x + m.width), y1 = Math.min(c.y + c.height, m.y + m.height)
      return { c, r: { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } }
    })
    .filter(({ r }) => r.w > 40 && r.h > 40)
    .sort((a, b) => a.r.x - b.r.x)
}

let busy = false
/** Capture every window on `ws` (only if it is showing). One grim per window, a quarter scale. */
export async function capture(ws: Hyprland.Workspace | null | undefined) {
  if (!ws || busy) return
  const cs = visibleClients(ws)
  if (!cs.length) return
  busy = true
  try {
    // full resolution, jpeg: grim's -s with -g leaves the scaled content in a corner of a
    // full-size canvas (grim 1.4); GTK scales the picture down instead
    await Promise.all(cs.map(({ c, r }) => execAsync(["grim", "-t", "jpeg", "-q", "70", "-g", `${r.x},${r.y} ${r.w}x${r.h}`, pathFor(c.address)]).then(() => geom.set(c.address, r)).catch(() => {})))
    setStamp((s) => s + 1)
  } finally { busy = false }
}

export const hasThumb = (address: string) => Gio.File.new_for_path(pathFor(address)).query_exists(null)

/** Capture every showing workspace now (fresh thumbs before a strip opens on the active one). */
export const captureShowing = () => Promise.all(hypr.get_monitors().map((m) => capture(m.activeWorkspace)))

// after a switch the new workspace's windows are up ~half a second later; debounce, one capture
let pending: Timer | null = null
hypr.connect("notify::focused-workspace", () => {
  pending?.cancel()
  pending = timeout(700, () => capture(hypr.focusedWorkspace))
})
// gone windows leave their thumbs; a sweep at start keeps the dir honest
hypr.connect("client-removed", (_, address: string) => { try { Gio.File.new_for_path(pathFor(address)).delete(null) } catch { /* none */ } })
timeout(3000, () => {
  try {
    const live = new Set(hypr.get_clients().map((c) => c.address.replace(/^0x/, "")))
    const e = Gio.File.new_for_path(DIR).enumerate_children("standard::name", 0, null)
    let i: Gio.FileInfo | null
    while ((i = e.next_file(null))) { const n = i.get_name().replace(/\.(png|jpg)$/, ""); if (!live.has(n)) try { Gio.File.new_for_path(`${DIR}/${i.get_name()}`).delete(null) } catch { /* none */ } }
  } catch { /* first run */ }
  captureShowing()
})
