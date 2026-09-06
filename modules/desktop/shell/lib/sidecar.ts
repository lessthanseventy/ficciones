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
import { execAsync } from "ags/process"
import { hypr, addr } from "./hypr"

const WIDTH = 0.34 // of the monitor
const GAP = 12 // general:gaps_out

type MonitorJson = { name: string; x: number; y: number; width: number; height: number; reserved: [number, number, number, number] }
type Sidecar = { address: string; zone: Astal.Window }

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

export const isSidecar = (c: Hyprland.Client) => [...sidecars.values()].some((s) => s.address === c.address)

export async function pinSidecar(c: Hyprland.Client) {
  const name = c.get_monitor().name
  const prev = sidecars.get(name)
  if (prev && prev.address !== c.address) {
    const old = hypr.get_client(prev.address)
    if (old) await unpinSidecar(old)
    else { prev.zone.destroy(); sidecars.delete(name) }
  }
  const m = await monitorJson(name)
  if (!m) return
  const [rl, rt, , rb] = m.reserved // rail + bar; no sidecar zone yet on this monitor
  const col = Math.round(m.width * WIDTH)
  const a = addr(c)
  hypr.dispatch("setfloating", a)
  hypr.dispatch("resizewindowpixel", `exact ${col - GAP} ${m.height - rt - rb - 2 * GAP},${a}`)
  hypr.dispatch("movewindowpixel", `exact ${m.x + rl + GAP} ${m.y + rt + GAP},${a}`)
  if (!c.pinned) hypr.dispatch("pin", a)
  sidecars.set(name, { address: c.address, zone: makeZone(name, col) })
}

export async function unpinSidecar(c: Hyprland.Client) {
  const name = c.get_monitor().name
  const a = addr(c)
  if (c.pinned) hypr.dispatch("pin", a)
  hypr.dispatch("settiled", a)
  const s = sidecars.get(name)
  if (s && s.address === c.address) { s.zone.destroy(); sidecars.delete(name) }
}

export const toggleSidecar = (c: Hyprland.Client) => (isSidecar(c) ? unpinSidecar(c) : pinSidecar(c))

// A sidecar that closes must give its column back.
hypr.connect("client-removed", (_, address: string) => {
  for (const [name, s] of sidecars) if (s.address === address) { s.zone.destroy(); sidecars.delete(name) }
})
