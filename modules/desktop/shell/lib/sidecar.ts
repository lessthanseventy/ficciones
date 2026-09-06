// The sidecar: a window pinned to the LEFT of every workspace on its monitor, with the tiled
// columns of each workspace laid out beside it (Andrew, 2026-09-05). Hyprland only pins floating
// windows, so pin = float + size to a left column + pin + reserve that column on the monitor
// (hyprctl keyword monitor <name>,addreserved) so the scrolling layout starts to its right.
// Unpin reverses all of it. One sidecar per monitor.
import Hyprland from "gi://AstalHyprland"
import { execAsync } from "ags/process"
import { hypr } from "./hypr"

const WIDTH = 0.34 // of the monitor
const GAP = 12 // general:gaps_out

type MonitorJson = { name: string; x: number; y: number; width: number; height: number; reserved: [number, number, number, number] }

const sidecars = new Map<string, string>() // monitor name → client address

async function monitorJson(name: string): Promise<MonitorJson | undefined> {
  const list = JSON.parse(await execAsync(["hyprctl", "monitors", "-j"])) as MonitorJson[]
  return list.find((m) => m.name === name)
}

const reserve = (name: string, left: number) =>
  execAsync(["hyprctl", "keyword", "monitor", `${name},addreserved,0,0,${left},0`])

export const isSidecar = (c: Hyprland.Client) => [...sidecars.values()].includes(c.address)

export async function pinSidecar(c: Hyprland.Client) {
  const name = c.get_monitor().name
  const prev = sidecars.get(name)
  if (prev && prev !== c.address) {
    const old = hypr.get_client(prev)
    if (old) await unpinSidecar(old)
  }
  // base reserved area (rail + bar); a previous sidecar's reservation is already cleared above
  await reserve(name, 0)
  const m = await monitorJson(name)
  if (!m) return
  const [rl, rt, rr, rb] = m.reserved
  const col = Math.round(m.width * WIDTH)
  const a = `address:${c.address}`
  hypr.dispatch("setfloating", a)
  hypr.dispatch("resizewindowpixel", `exact ${col - GAP} ${m.height - rt - rb - 2 * GAP},${a}`)
  hypr.dispatch("movewindowpixel", `exact ${m.x + rl + GAP} ${m.y + rt + GAP},${a}`)
  if (!c.pinned) hypr.dispatch("pin", a)
  await reserve(name, col + GAP)
  sidecars.set(name, c.address)
}

export async function unpinSidecar(c: Hyprland.Client) {
  const name = c.get_monitor().name
  const a = `address:${c.address}`
  if (c.pinned) hypr.dispatch("pin", a)
  hypr.dispatch("settiled", a)
  if (sidecars.get(name) === c.address) {
    sidecars.delete(name)
    await reserve(name, 0)
  }
}

export const toggleSidecar = (c: Hyprland.Client) => (isSidecar(c) ? unpinSidecar(c) : pinSidecar(c))

// A sidecar that closes must give its column back.
hypr.connect("client-removed", (_, address: string) => {
  for (const [name, addr] of sidecars) if (addr === address) { sidecars.delete(name); reserve(name, 0) }
})
