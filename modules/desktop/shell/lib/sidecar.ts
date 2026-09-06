// The sidecar: a window pinned to the LEFT of every workspace on its monitor, with the tiled
// columns of each workspace laid out beside it (Andrew, 2026-09-05). Hyprland only pins floating
// windows, so pin = float + size to a left column + pin, and the column is held open by an
// invisible layer-shell window with an exclusive zone on the TOP layer, created after the rail
// and bar so it is arranged after them (`hyprctl keyword monitor addreserved` pushed the bar
// too). Unpin reverses all of it. One sidecar per monitor. It should not feel like a special
// window (Andrew, 2026-09-05): the normal resize keybinds size it and the column follows; what
// marks it is a thicker border in the accent (per-window setprop — no plugin).
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import GLib from "gi://GLib?version=2.0"
import Gtk from "gi://Gtk?version=4.0"
import LayerShell from "gi://Gtk4LayerShell?version=1.0"
import { execAsync } from "ags/process"
import { timeout, interval, type Timer } from "ags/time"
import { query } from "./hyprsock"
import { hypr, addr } from "./hypr"
import { PALETTE } from "./palette"

const WIDTH = 0.34 // of the monitor, until resized
const GAP = 12 // general:gaps_out
const MIN = 0.18, MAX = 0.65

type MonitorJson = { name: string; x: number; y: number; width: number; height: number; reserved: [number, number, number, number] }
type Sidecar = { address: string; zone: Astal.Window; col: number; m: MonitorJson; width: number }

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
    // TOP, like the rail: Hyprland hands out exclusive zones background→overlay, then in order
    // of creation within a layer, so this comes after the rail and the bar and sits beside them
    layer: Astal.Layer.TOP,
    anchor: Astal.WindowAnchor.LEFT | Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM,
    cssClasses: ["sidecar-zone"],
  })
  // an empty window sizes to GTK's 200px default whatever width-request says: a child fixes the
  // width, and the exclusive zone is asked for once the surface exists
  w.set_child(new Gtk.Box({ widthRequest: width, hexpand: true, vexpand: true, canTarget: false }))
  w.set_size_request(width, -1)
  w.visible = true
  // Astal's `exclusivity: EXCLUSIVE` (auto zone) does not take on this window inside the shell
  // (it does in a bare test app — unexplained, 2026-09-06), so the zone is set explicitly
  LayerShell.set_exclusive_zone(w, width)
  return w
}

/** Dispatches in order, as one batch, with Hyprland's answers logged (hypr.dispatch is fire-and-forget). */
async function batch(cmds: string[]) {
  try {
    const out = await execAsync(["hyprctl", "--batch", cmds.map((c) => `dispatch ${c}`).join("; ")])
    const bad = out.split("\n").filter((l) => l.trim() && l.trim() !== "ok")
    if (bad.length) console.error("sidecar:", bad.join(" | "))
  } catch (e) { console.error("sidecar:", String(e)) }
}

const placeCmds = (address: string, m: MonitorJson, col: number) => {
  const [rl, rt, , rb] = m.reserved
  const a = `address:0x${address.replace(/^0x/, "")}`
  return [`resizewindowpixel exact ${col - GAP} ${m.height - rt - rb - 2 * GAP},${a}`, `movewindowpixel exact ${m.x + rl + GAP} ${m.y + rt + GAP},${a}`]
}
/** Place the pinned window in a column `col` px wide on monitor `m`. */
const place = (address: string, m: MonitorJson, col: number) => batch(placeCmds(address, m, col))

// AstalHyprland's client size does not update on a resize (no event for it), so while a sidecar
// exists its size is read over the socket twice a second and the column follows.
let following: Timer | null = null
let settleUntil = 0 // our own relayout moves floating windows about; the poll waits it out
function startFollowing() {
  if (following) return
  following = interval(500, () => {
    if (!sidecars.size) { following?.cancel(); following = null; return }
    if (Date.now() < settleUntil) return
    let clients: { address: string; size: [number, number] }[] = []
    try { clients = JSON.parse(query("j/clients")) } catch { return }
    for (const [name, s] of sidecars) {
      const c = clients.find((x) => x.address === `0x${s.address.replace(/^0x/, "")}`)
      if (c && c.size[0] !== s.width) follow(name, c.size[0])
    }
  })
}

/** The column follows the window: after a resize keybind the zone takes the new width, and the
 * window is put back on the left edge at that width (clamped — a resize moves it as well). */
function follow(name: string, width: number) {
  const s = sidecars.get(name)
  if (!s) return
  const col = Math.max(Math.round(s.m.width * MIN), Math.min(Math.round(s.m.width * MAX), width + GAP))
  s.width = col - GAP
  if (col !== s.col) {
    s.col = col
    s.zone.set_size_request(col, -1)
    ;(s.zone.get_child() as Gtk.Box | null)?.set_size_request(col, -1)
    LayerShell.set_exclusive_zone(s.zone, col)
    widths.set(name, col / s.m.width); saveWidths()
    // the tiled columns re-fit on a relayout, which also shoves floating windows about: place
    // again after it and keep the poll quiet until things settle
    settleUntil = Date.now() + 1200
    timeout(80, relayout)
    timeout(400, () => place(s.address, s.m, col))
  }
  place(s.address, s.m, col)
}

/**
 * The scrolling layout only re-fits its columns to the usable area on a config change, so the
 * reserved column would sit over the first tiled one until then: re-set gaps_out to itself.
 */
async function relayout() {
  try {
    const g = JSON.parse(await execAsync(["hyprctl", "getoption", "general:gaps_out", "-j"])).custom as string
    await execAsync(["hyprctl", "keyword", "general:gaps_out", g])
    // and the visible columns of the active workspace re-fit beside the column, so the first
    // tiled one does not hang under it (other workspaces re-fit when you next `fit` there)
    await execAsync(["hyprctl", "dispatch", "layoutmsg", "fit visible"])
  } catch (e) { console.error("sidecar relayout:", String(e)) }
}

const rgb = (hex: string) => `rgb(${hex.replace("#", "")})`
/** The mark of a sidecar: a thicker border in the accent, dim when unfocused. `unset` restores. */
// setprop is a dispatcher in Hyprland 0.56 (snake_case props). `unset` restores border_size but
// leaves the colour props as an EMPTY gradient (no border at all), so unmarking writes the
// global gradients back explicitly.
async function mark(a: string, on: boolean) {
  if (on) return batch([`setprop ${a} border_size 3`, `setprop ${a} active_border_color ${rgb(PALETTE.pink)}`, `setprop ${a} inactive_border_color ${rgb(PALETTE.dim)}`])
  // getoption gives "aarrggbb aarrggbb 45deg"; setprop only renders rgba()/rgb() stops
  const opt = async (k: string) => {
    const raw = ((JSON.parse(await execAsync(["hyprctl", "getoption", k, "-j"])).custom as string) || "ffffffff").trim()
    return raw.split(/\s+/).map((t) => (/^[0-9a-f]{8}$/i.test(t) ? `rgba(${t.slice(2)}${t.slice(0, 2)})` : t)).join(" ")
  }
  const [act, ina] = await Promise.all([opt("general:col.active_border"), opt("general:col.inactive_border")])
  return batch([`setprop ${a} border_size unset`, `setprop ${a} active_border_color ${act}`, `setprop ${a} inactive_border_color ${ina}`])
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
  // a fullscreen or maximised window (hyprscroller's maximise counts) cannot float, and a tiled
  // one cannot pin — Hyprland refused both silently until the batch reported them
  await batch([`fullscreenstate 0 0,${a}`, `setfloating ${a}`, ...placeCmds(c.address, m, col), ...(c.pinned ? [] : [`pin ${a}`])])
  mark(a, true)
  settleUntil = Date.now() + 1200
  timeout(80, relayout)
  timeout(400, () => place(c.address, m, col))
  sidecars.set(name, { address: c.address, zone: makeZone(name, col), col, m, width: col - GAP })
  startFollowing()
}

function drop(name: string) {
  const s = sidecars.get(name)
  if (!s) return
  const c = hypr.get_client(s.address)
  if (c) mark(addr(c), false)
  s.zone.destroy(); sidecars.delete(name)
}

export async function unpinSidecar(c: Hyprland.Client) {
  const name = c.get_monitor().name
  const a = addr(c)
  const s = sidecars.get(name)
  if (s && s.address === c.address) drop(name)
  await batch([...(c.pinned ? [`pin ${a}`] : []), `settiled ${a}`])
  timeout(80, relayout)
}

export const toggleSidecar = (c: Hyprland.Client) => (isSidecar(c) ? unpinSidecar(c) : pinSidecar(c))
/**
 * `astal-shell colresize ±0.05`: the Super+;/' keys. A focused sidecar changes width by that
 * fraction of the monitor (the column follows); anything else is the layout's own colresize.
 */
export function colresize(arg: string) {
  const c = hypr.focusedClient
  const s = c && [...sidecars.entries()].find(([, x]) => x.address === c.address)
  if (!c || !s) return batch([`layoutmsg colresize ${arg}`])
  const [name, side] = s
  const d = Number(arg) || 0
  follow(name, side.width + Math.round(side.m.width * d))
}

/** `astal-shell sidecar [toggle|pin|unpin]` on the focused window — for a keybind. */
export function sidecarVerb(what = "toggle") {
  const c = hypr.focusedClient
  if (!c) return
  if (what === "pin") pinSidecar(c)
  else if (what === "unpin") unpinSidecar(c)
  else toggleSidecar(c)
}

// A sidecar that closes must give its column back.
hypr.connect("client-removed", (_, address: string) => {
  for (const [name, s] of sidecars) if (s.address === address) { drop(name); timeout(80, relayout) }
})
