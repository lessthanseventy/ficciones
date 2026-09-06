// The sidecar: a window pinned to the LEFT of every workspace on its monitor, with the tiled
// columns of each workspace laid out beside it (Andrew, 2026-09-05). Hyprland only pins floating
// windows, so pin = float + size to a left column + pin, and the column is held open by an
// invisible layer-shell window with an EXCLUSIVE zone (layer BOTTOM, so the bar on TOP is
// arranged first and keeps its full width — `hyprctl keyword monitor addreserved` pushed the bar
// too). Unpin reverses all of it. One sidecar per monitor.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Gtk from "gi://Gtk?version=4.0"
import GLib from "gi://GLib?version=2.0"
import { execAsync } from "ags/process"
import { hypr, addr } from "./hypr"
import { query } from "./hyprsock"

const WIDTH = 0.34 // of the monitor, until dragged
const GAP = 12 // general:gaps_out
const MIN = 0.18, MAX = 0.65

type MonitorJson = { name: string; x: number; y: number; width: number; height: number; reserved: [number, number, number, number] }
type Sidecar = { address: string; zone: Astal.Window; handle: Astal.Window; col: number; m: MonitorJson }

// The dragged width outlives the shell: one line per monitor in the state dir.
const STATE = `${GLib.get_user_state_dir()}/astal-shell/sidecar-width`
const widths = new Map<string, number>() // monitor → fraction
try {
  const [ok, bytes] = GLib.file_get_contents(STATE)
  if (ok) for (const l of new TextDecoder().decode(bytes).split("\n")) { const [n, f] = l.split(" "); if (n && Number(f) > 0) widths.set(n, Number(f)) }
} catch { /* first run */ }
function saveWidths() {
  try {
    GLib.mkdir_with_parents(GLib.path_get_dirname(STATE), 0o755)
    GLib.file_set_contents(STATE, [...widths].map(([n, f]) => `${n} ${f.toFixed(3)}`).join("\n"))
  } catch (e) { console.error("sidecar width:", String(e)) }
}

const sidecars = new Map<string, Sidecar>() // monitor name → sidecar

async function monitorJson(name: string): Promise<MonitorJson | undefined> {
  const list = JSON.parse(await execAsync(["hyprctl", "monitors", "-j"])) as MonitorJson[]
  return list.find((m) => m.name === name)
}

function gdkMonitor(name: string): Gdk.Monitor | undefined {
  const mons = Gdk.Display.get_default()!.get_monitors()
  for (let i = 0; i < mons.get_n_items(); i++) {
    const m = mons.get_item(i) as Gdk.Monitor
    if (m.connector === name) return m
  }
}

function makeZone(name: string, width: number): Astal.Window {
  const w = new Astal.Window({
    application: app,
    namespace: "astal-shell-sidecar",
    name: `sidecar-${name}`,
    gdkmonitor: gdkMonitor(name),
    layer: Astal.Layer.BOTTOM,
    exclusivity: Astal.Exclusivity.EXCLUSIVE,
    anchor: Astal.WindowAnchor.LEFT | Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM,
    cssClasses: ["sidecar-zone"],
    widthRequest: width,
    defaultWidth: width,
    visible: true,
  })
  return w
}

/** Place the pinned window in a column `col` px wide on monitor `m`. */
function place(address: string, m: MonitorJson, col: number) {
  const [rl, rt, , rb] = m.reserved
  const a = `address:0x${address.replace(/^0x/, "")}`
  hypr.dispatch("resizewindowpixel", `exact ${col - GAP} ${m.height - rt - rb - 2 * GAP},${a}`)
  hypr.dispatch("movewindowpixel", `exact ${m.x + rl + GAP} ${m.y + rt + GAP},${a}`)
}

/**
 * The grab handle: a 12px layer window in the gap right of the column (layer TOP, so it sits
 * over the workspace gap; the zone itself is on BOTTOM under every window). Dragging reads the
 * pointer from Hyprland — the handle moves under the pointer as it drags, so widget-relative
 * offsets would chase themselves.
 */
function makeHandle(name: string, m: MonitorJson, col: number): Astal.Window {
  const [rl] = m.reserved
  const w = new Astal.Window({
    application: app,
    namespace: "astal-shell-sidecar-handle",
    name: `sidecar-handle-${name}`,
    gdkmonitor: gdkMonitor(name),
    layer: Astal.Layer.TOP,
    exclusivity: Astal.Exclusivity.IGNORE,
    anchor: Astal.WindowAnchor.LEFT | Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM,
    cssClasses: ["sidecar-handle"],
    marginLeft: rl + col,
    widthRequest: GAP,
    defaultWidth: GAP,
  })
  const grip = new Gtk.Box({ cssClasses: ["grip"], hexpand: true, vexpand: true, cursor: Gdk.Cursor.new_from_name("col-resize", null) })
  w.set_child(grip)
  const drag = new Gtk.GestureDrag()
  let last = 0
  drag.connect("drag-update", () => {
    const s = sidecars.get(name)
    if (!s) return
    let x = 0
    try { x = Number(query("cursorpos").split(",")[0]) } catch { return }
    const frac = Math.max(MIN, Math.min(MAX, (x - m.x - rl - GAP / 2) / m.width))
    const next = Math.round(frac * m.width)
    if (Math.abs(next - last) < 6) return
    last = next
    resize(name, next)
  })
  drag.connect("drag-end", () => {
    const s = sidecars.get(name)
    if (s) { widths.set(name, s.col / m.width); saveWidths() }
  })
  grip.add_controller(drag)
  w.visible = true
  return w
}

function resize(name: string, col: number) {
  const s = sidecars.get(name)
  if (!s) return
  s.col = col
  s.zone.set_size_request(col, -1)
  s.zone.defaultWidth = col
  s.handle.marginLeft = s.m.reserved[0] + col
  place(s.address, s.m, col)
}

export const isSidecar = (c: Hyprland.Client) => [...sidecars.values()].some((s) => s.address === c.address)

export async function pinSidecar(c: Hyprland.Client) {
  const name = c.get_monitor().name
  const prev = sidecars.get(name)
  if (prev && prev.address !== c.address) {
    const old = hypr.get_client(prev.address)
    if (old) await unpinSidecar(old)
    else drop(name)
  }
  const m = await monitorJson(name)
  if (!m) return
  // reserved = rail + bar; no sidecar zone yet on this monitor
  const col = Math.round(m.width * (widths.get(name) ?? WIDTH))
  const a = addr(c)
  hypr.dispatch("setfloating", a)
  place(c.address, m, col)
  if (!c.pinned) hypr.dispatch("pin", a)
  sidecars.set(name, { address: c.address, zone: makeZone(name, col), handle: makeHandle(name, m, col), col, m })
}

function drop(name: string) {
  const s = sidecars.get(name)
  if (!s) return
  s.zone.destroy(); s.handle.destroy(); sidecars.delete(name)
}

export async function unpinSidecar(c: Hyprland.Client) {
  const name = c.get_monitor().name
  const a = addr(c)
  if (c.pinned) hypr.dispatch("pin", a)
  hypr.dispatch("settiled", a)
  const s = sidecars.get(name)
  if (s && s.address === c.address) drop(name)
}

export const toggleSidecar = (c: Hyprland.Client) => (isSidecar(c) ? unpinSidecar(c) : pinSidecar(c))

// A sidecar that closes must give its column back.
hypr.connect("client-removed", (_, address: string) => {
  for (const [name, s] of sidecars) if (s.address === address) drop(name)
})
