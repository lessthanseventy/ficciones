// Window thumbnails for the workspace strips: grim captures each mapped window on the workspace
// that just became visible (and the ones showing at start) as itself (`grim -T`, by the window's
// `stableId`), so a column the scrolling layout parks past the monitor's edge comes out whole, into
// the cache dir keyed by window address. A hidden workspace shows its windows as they last were.
// `stamp` bumps after a capture so pictures reload.
import Gio from "gi://Gio?version=2.0"
import GLib from "gi://GLib?version=2.0"
import Hyprland from "gi://AstalHyprland"
import Gdk from "gi://Gdk?version=4.0"
import GdkPixbuf from "gi://GdkPixbuf?version=2.0"
import { createState } from "ags"
import { execAsync } from "ags/process"
import { timeout, interval, type Timer } from "ags/time"
import { hypr } from "./hypr"

const DIR = `${GLib.get_user_cache_dir()}/astal-shell/thumbs`
GLib.mkdir_with_parents(DIR, 0o755)
export const pathFor = (address: string) => `${DIR}/${address.replace(/^0x/, "")}.jpg`
export const [stamp, setStamp] = createState(0)

type Rect = { x: number; y: number; w: number; h: number }
/** The captured rectangle per window: the whole window, wherever the layout has it. */
export const geom = new Map<string, Rect>()

/** Windows on a workspace that is on screen right now, whole, left to right. */
function visibleClients(ws: Hyprland.Workspace): { c: Hyprland.Client; r: Rect }[] {
  if (!hypr.get_monitors().some((m) => m.activeWorkspace?.id === ws.id)) return []
  return hypr.get_clients()
    .filter((c) => c.workspace?.id === ws.id && c.mapped && c.width > 40 && c.height > 40)
    .map((c) => ({ c, r: { x: c.x, y: c.y, w: c.width, h: c.height } }))
    .sort((a, b) => a.r.x - b.r.x)
}

/** Every window's ext-foreign-toplevel-list identifier (Hyprland's `stableId`), by address */
async function stableIds(): Promise<Map<string, string>> {
  const cs = JSON.parse(await execAsync(["hyprctl", "clients", "-j"])) as { address: string; stableId: string }[]
  return new Map(cs.map((c) => [c.address.replace(/^0x/, ""), c.stableId]))
}

let busy = false
/** Capture every window on `ws` (only if it is showing). One grim per window, a quarter scale. */
export async function capture(ws: Hyprland.Workspace | null | undefined) {
  if (!ws || busy) return
  const cs = visibleClients(ws)
  if (!cs.length) return
  busy = true
  try {
    // full resolution, jpeg; GTK scales the picture down
    const ids = await stableIds()
    await Promise.all(cs.map(({ c, r }) => {
      const id = ids.get(c.address.replace(/^0x/, ""))
      return id ? execAsync(["grim", "-t", "jpeg", "-q", "70", "-T", id, pathFor(c.address)]).then(() => geom.set(c.address, r)).catch(() => {}) : null
    }))
    setStamp((s) => s + 1)
  } finally { busy = false }
}

export const hasThumb = (address: string) => Gio.File.new_for_path(pathFor(address)).query_exists(null)

/** The thumb as a texture already scaled to `h` px tall — a Picture at natural size then IS the thumbnail. */
export function texture(address: string, h: number): Gdk.Texture | null {
  try {
    const pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(pathFor(address), -1, h, true)
    return pb ? Gdk.Texture.new_for_pixbuf(pb) : null
  } catch { return null }
}

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
// and while a strip is open every showing workspace refreshes every few seconds, so it is
// never far behind. Not at idle: a capture is a grim per window and every strip's pictures
// (hidden ones too) decode their jpeg again on the stamp — measured at ~2% of a core all day.
let watchers = 0
let live: Timer | null = null
export function watchThumbs(pop: { connect(sig: string, cb: () => void): number }) {
  pop.connect("show", () => { if (++watchers === 1) live = interval(5000, () => captureShowing()) })
  pop.connect("hide", () => { if (--watchers <= 0) { watchers = 0; live?.cancel(); live = null } })
}
timeout(3000, () => {
  try {
    const live = new Set(hypr.get_clients().map((c) => c.address.replace(/^0x/, "")))
    const e = Gio.File.new_for_path(DIR).enumerate_children("standard::name", 0, null)
    let i: Gio.FileInfo | null
    while ((i = e.next_file(null))) { const n = i.get_name().replace(/\.(png|jpg)$/, ""); if (!live.has(n)) try { Gio.File.new_for_path(`${DIR}/${i.get_name()}`).delete(null) } catch { /* none */ } }
  } catch { /* first run */ }
  captureShowing()
})
