// The sidecar: a window pinned to the LEFT of every workspace on its monitor, with the tiled
// columns of each workspace laid out beside it (Andrew, 2026-09-05). Hyprland only pins floating
// windows, so pin = float + size to a left column + pin, and the column is held open by an
// an invisible layer window on TOP with an EXPLICIT exclusive zone (gtk4-layer-shell), created
// after the rail and the bar so Hyprland arranges it after them and the bar keeps its width.
// Explicit, because an invisible content-less window sizes to GTK's 200px default and the auto
// zone reads 0 (bisected 2026-09-06); the surface's size does not matter, the zone does. Its
// input region is empty, so clicks fall through to the pinned window under it. Widening the
// rail's own zone instead squeezed the bar and did not shrink back on unpin. Unpin reverses
// all of it. One sidecar per monitor. It should not feel like a special
// window (Andrew, 2026-09-05): the normal resize keybinds size it and the column follows. It is
// a regular window with a thicker border (3px, per-window setprop) whose OUTER edge sits where a
// tiled window's border edge does, and one extra ring around it (Andrew, 2026-09-07).
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Hyprland from "gi://AstalHyprland"
import GLib from "gi://GLib?version=2.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import LayerShell from "gi://Gtk4LayerShell?version=1.0"
import Cairo from "cairo"
import { execAsync } from "ags/process"
import { L, dispatch, evalLua } from "./hyprlua"
import { timeout, interval, type Timer } from "ags/time"
import { query } from "./hyprsock"
import { hypr, addr } from "./hypr"
import { createState } from "ags"

const WIDTH = 0.34 // of the monitor, until resized
const GAP = 12 // general:gaps_out
const MIN = 0.18, MAX = 0.65
// the sidecar's border: thicker than general:border_size (2), set per window; the surface sits
// inside the gap by this much, so the border's outer edge lines up with the tiled windows'
const border = 3
const setBorder = (a: string, on: boolean) => L.setProp(a, "border_size", on ? String(border) : "unset")
/** The sidecar's address per monitor name — the bar's pin/unpin label reads this, not Hyprland's
 * `pinned` (the quake terminal and PiP are pinned too, and are not sidecars). */
export const [sidecarAddrs, setSidecarAddrs] = createState<Record<string, string>>({})
const publish = () => { setSidecarAddrs(Object.fromEntries([...sidecars].map(([n, s]) => [n, s.address]))); savePins() }

type MonitorJson = { name: string; x: number; y: number; width: number; height: number; reserved: [number, number, number, number] }
type Sidecar = { address: string; zone: Astal.Window; frame: Astal.Window; col: number; m: MonitorJson; width: number }

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

// Which window is the sidecar outlives the shell too: Hyprland keeps it pinned and floating in
// its column across a shell restart, but the zone and the ring died with the process, so the
// tiled columns slid under it and Andrew had to pin it again by hand (2026-09-07). One line per
// monitor, `name address`; a window address is good for the life of the Hyprland session.
const PINS = `${GLib.get_user_state_dir()}/astal-shell/sidecar-pinned`
function savePins() {
  try {
    GLib.mkdir_with_parents(GLib.path_get_dirname(PINS), 0o755)
    GLib.file_set_contents(PINS, [...sidecars].map(([n, s]) => `${n} ${s.address}`).join("\n"))
  } catch (e) { console.error("sidecar pins:", String(e)) }
}
/** At start: pin again whatever the saved lines name, if it is still there, pinned and floating on
 * that monitor. AstalHyprland fills its client list asynchronously, so this waits for it. */
export async function adoptSidecars(tries = 40) {
  let lines: string[] = []
  try { const [ok, bytes] = GLib.file_get_contents(PINS); if (ok) lines = new TextDecoder().decode(bytes).split("\n").filter(Boolean) } catch { return }
  if (!lines.length) return
  const again = () => { if (tries > 0) timeout(250, () => adoptSidecars(tries - 1)) }
  if (!hypr.get_clients().length) return again()
  for (const l of lines) {
    const [name, address] = l.split(" ")
    const c = hypr.get_client(address)
    if (!(c && c.pinned && c.floating && c.get_monitor()?.name === name)) continue
    // the column and ring are placed inside the monitor's reserved area — the rail and bar's
    // exclusive zones — which is empty until this shell's own layers have mapped: adopted too
    // early, the ring ran under the rail (Andrew, 2026-09-07)
    const m = await monitorJson(name)
    if (!m || (m.reserved[0] === 0 && m.reserved[1] === 0)) return again()
    pinSidecar(c)
  }
}

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

function makeZone(name: string, col: number): Astal.Window {
  const w = new Astal.Window({
    application: app,
    namespace: "astal-shell-sidecar",
    name: `sidecar-${name}`,
    gdkmonitor: gdkMonitor(name),
    layer: Astal.Layer.TOP,
    anchor: Astal.WindowAnchor.LEFT | Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM,
    cssClasses: ["sidecar-zone"],
    visible: true,
  })
  LayerShell.set_exclusive_zone(w, col)
  w.get_surface()?.set_input_region(new Cairo.Region())
  return w
}

// The double border: an outer pink ring the shell draws — a transparent layer window framing
// the column, always pink: "this is the sidecar" — and Hyprland's own border inside it carrying
// focus as every window does, amber focused / dim not (Andrew, 2026-09-06). No plugin: borders-plus-plus rings every window and its only per-window
// switch (`decorate`) would take the shadows off everything else.
const RING = 2, RING_GAP = 3
const inset = () => border + RING_GAP + RING
function makeFrame(name: string, m: MonitorJson, col: number, address: string): Astal.Window {
  const [rl, rt, , rb] = m.reserved
  const inset = border + RING_GAP + RING
  const w = new Astal.Window({
    application: app,
    namespace: "astal-shell-sidecar-frame",
    name: `sidecar-frame-${name}`,
    gdkmonitor: gdkMonitor(name),
    layer: Astal.Layer.TOP,
    exclusivity: Astal.Exclusivity.IGNORE,
    anchor: Astal.WindowAnchor.LEFT | Astal.WindowAnchor.TOP,
    marginLeft: rl + GAP + border - inset,
    marginTop: rt + GAP + border - inset,
    cssClasses: ["sidecar-frame-win"],
  })
  const ring = new Gtk.Box({ cssClasses: ["sidecar-frame"], hexpand: true, vexpand: true, canTarget: false })
  w.set_child(ring)
  frameSize(w, surfW(col) + 2 * inset, m.height - rt - rb - 2 * GAP - 2 * border + 2 * inset)
  w.visible = true
  w.get_surface()?.set_input_region(new Cairo.Region())
  return w
}

// set_size_request alone is a MINIMUM: GTK grows the surface to meet a larger one and never
// shrinks it back, so the ring stayed at its widest after a narrower resize (2026-09-07).
function frameSize(w: Astal.Window, width: number, height: number) {
  w.set_size_request(width, height)
  w.set_default_size(width, height)
}

const batch = (cmds: string[]) => dispatch(...cmds)

// the column is `col` wide from the monitor's left edge; the window's box (border included)
// fills it past the gap, as a tiled column's would: surface = box less the border on each side
const surfW = (col: number) => col - GAP - 2 * border
const colOf = (surfaceWidth: number) => surfaceWidth + GAP + 2 * border
const placeCmds = (address: string, m: MonitorJson, col: number) => {
  const [rl, rt, , rb] = m.reserved
  const a = `address:0x${address.replace(/^0x/, "")}`
  return [L.resizeExact(a, surfW(col), m.height - rt - rb - 2 * GAP - 2 * border), L.moveExact(a, m.x + rl + GAP + border, m.y + rt + GAP + border)]
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
    let clients: { address: string; size: [number, number]; pinned: boolean; monitor: number; mapped: boolean }[] = []
    try { clients = JSON.parse(query("j/clients")) } catch { return }
    for (const [name, s] of sidecars) {
      const c = clients.find((x) => x.address === `0x${s.address.replace(/^0x/, "")}`)
      if (c && c.size[0] !== s.width) follow(name, c.size[0])
      // the ring is a layer surface, above every window: while ANOTHER pinned window is up on
      // this monitor (the quake terminal) it would bleed through, so it hides
      if (c) s.frame.visible = !ringOff && !clients.some((x) => x.pinned && x.mapped && x.monitor === c.monitor && x.address !== c.address)
    }
  })
}

/** The column follows the window: after a resize keybind the zone takes the new width, and the
 * window is put back on the left edge at that width (clamped — a resize moves it as well). */
function follow(name: string, width: number) {
  const s = sidecars.get(name)
  if (!s) return
  const col = Math.max(Math.round(s.m.width * MIN), Math.min(Math.round(s.m.width * MAX), colOf(width)))
  s.width = surfW(col)
  if (col !== s.col) {
    s.col = col
    LayerShell.set_exclusive_zone(s.zone, col)
    frameSize(s.frame, surfW(col) + 2 * inset(), s.frame.get_height())
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
    // under the .lua config getoption reports the gaps as `css` ("12 12 12 12", top right
    // bottom left) and hl.config wants them back as a table
    const css = JSON.parse(await execAsync(["hyprctl", "getoption", "general:gaps_out", "-j"])).css as string
    const [t, r, b, l] = css.trim().split(/\s+/).map(Number)
    await evalLua(`hl.config({ general = { gaps_out = { top = ${t}, right = ${r}, bottom = ${b}, left = ${l} } } })`)
  } catch (e) { console.error("sidecar relayout:", String(e)) }
  // and the visible columns of the active workspace re-fit beside the column, so the first
  // tiled one does not hang under it (other workspaces re-fit when you next `fit` there);
  // nothing to fit when that workspace has no tiled window ("can't fit" otherwise); fit works
  // from the focused window, so a focused sidecar cannot fit — the layout re-fits its columns
  // to the reserved area on its own anyway
  const f = hypr.focusedClient
  if (f && f.mapped && !f.floating) { await dispatch(L.layout("fit visible")); return }
  // a focused sidecar (a pin from the bar, the adoption at start): fit from a tiled window on
  // the shown workspace and come back — the click-floorp-and-back Andrew did by hand (2026-09-07)
  const ws = (f?.get_monitor() ?? hypr.focusedMonitor)?.activeWorkspace?.id
  const t = hypr.get_clients().find((x) => x.workspace?.id === ws && x.mapped && !x.floating)
  if (t) await batch([L.focusWindow(addr(t)), L.layout("fit visible"), ...(f ? [L.focusWindow(addr(f))] : [])])
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
  await batch([L.fullscreenState(a, 0, 0), L.float(a, "on"), setBorder(a, true), ...placeCmds(c.address, m, col), ...(c.pinned ? [] : [L.pin(a)])])
  settleUntil = Date.now() + 1200
  timeout(80, relayout)
  timeout(400, () => place(c.address, m, col))
  sidecars.set(name, { address: c.address, zone: makeZone(name, col), frame: makeFrame(name, m, col, c.address), col, m, width: surfW(col) })
  publish()
  startFollowing()
}

function drop(name: string) {
  const s = sidecars.get(name)
  if (!s) return
  const c = hypr.get_client(s.address)
  if (c) batch([setBorder(addr(c), false)])
  s.zone.destroy(); s.frame.destroy()
  sidecars.delete(name)
  publish()
}

export async function unpinSidecar(c: Hyprland.Client) {
  const name = c.get_monitor().name
  const a = addr(c)
  const s = sidecars.get(name)
  if (s && s.address === c.address) drop(name)
  // the layout tiles it after the last column; a former sidecar goes back to the FRONT of the
  // workspace (Andrew, 2026-09-07): one swap left per column, in the SAME batch as the
  // float-off so the window makes one move, not a hop to the end and back (`move -col` only
  // scrolls and movewindow l merges into the neighbour's column; swapcol reorders)
  const ws = c.workspace?.id
  const cols = new Set(hypr.get_clients().filter((x) => x.workspace?.id === ws && x.mapped && !x.floating && x.address !== c.address).map((x) => x.x))
  await batch([...(c.pinned ? [L.pin(a)] : []), L.float(a, "off"), ...Array.from(cols, () => L.layout("swapcol l"))])
  timeout(80, relayout)
}

export const toggleSidecar = (c: Hyprland.Client) => (isSidecar(c) ? unpinSidecar(c) : pinSidecar(c))
/**
 * `astal-shell colresize ±0.05`: the Super+;/' keys. A focused sidecar changes width by that
 * fraction of the monitor (the column follows); anything else is the layout's own colresize.
 */
export function colresize(arg: string) {
  // words, not signed numbers: `ags request` reads "-0.05" as a flag
  const d = arg === "narrower" ? -0.05 : arg === "wider" ? 0.05 : Number(arg) || 0
  const c = hypr.focusedClient
  const s = c && [...sidecars.entries()].find(([, x]) => x.address === c.address)
  if (!c || !s) return batch([L.layout(`colresize ${d > 0 ? "+" : ""}${d}`)])
  const [name, side] = s
  follow(name, side.width + Math.round(side.m.width * d))
}

/**
 * `astal-shell focus l|r`: Super+H/L. The layout's focus ignores floating windows, so the
 * sidecar is stitched in by hand: from the sidecar, right goes to the leftmost tiled window
 * on screen; from that window, left goes to the sidecar; everything else is the layout's.
 */
export function focusDir(dir: "l" | "r") {
  const c = hypr.focusedClient
  const mon = c?.get_monitor()
  const s = mon && sidecars.get(mon.name)
  if (!c || !s) return batch([L.layout(`focus ${dir}`)])
  const ws = mon.activeWorkspace
  const tiled = hypr.get_clients()
    .filter((x) => x.workspace?.id === ws?.id && x.mapped && !x.floating && x.x < mon.x + mon.width)
    .sort((a, b) => a.x - b.x)
  const leftmost = tiled.find((x) => x.x + x.width > mon.x + s.col) ?? tiled[0]
  if (c.address === s.address) {
    if (dir === "r" && leftmost) return batch([L.focusWindow(addr(leftmost))])
    return
  }
  if (dir === "l" && leftmost && c.address === leftmost.address) return batch([L.focusWindow(`address:0x${s.address.replace(/^0x/, "")}`)])
  return batch([L.layout(`focus ${dir}`)])
}

/** `astal-shell sidecar [toggle|pin|unpin]` on the focused window — for a keybind. */
let ringOff = false
export function sidecarVerb(what = "toggle", arg?: string) {
  if (what === "ring") {
    // the quake script: the ring off before its slide, on after; the poll keeps it off while
    // another pinned window is up regardless
    ringOff = arg === "off"
    for (const s of sidecars.values()) s.frame.visible = !ringOff
    return
  }
  const c = hypr.focusedClient
  if (!c) return
  if (what === "pin") pinSidecar(c)
  else if (what === "unpin") unpinSidecar(c)
  else toggleSidecar(c)
}

// A sidecar that closes must give its column back.
hypr.connect("client-removed", (_, address: string) => {
  for (const [name, s] of sidecars) if (s.address === address) { drop(name); timeout(80, relayout) }
  refitSoon()
})

// The columns beside a sidecar re-fit when their number changes: a second tiled window opened
// later takes column_width and the layout CENTRES the focused column in the narrowed usable
// area — a dead band against the sidecar, the neighbour hanging off-screen (Andrew, 2026-09-08:
// "1 other window is fine, 2 makes a weird gap"). `fit visible` is what pin-time already runs.
hypr.connect("client-added", (_, c) => { if (!c.floating && sidecars.has(c.get_monitor()?.name ?? "")) refitSoon() })
// … and when a window moves between workspaces or the shown workspace changes (Andrew: "move one
// to a different workspace, scroll, move it back, scroll back") — the same refit, debounced.
const REFIT_EVENTS = new Set(["movewindow", "movewindowv2", "workspace", "workspacev2", "closewindow"])
hypr.connect("event", (_, ev: string) => { if (REFIT_EVENTS.has(ev)) refitSoon() })

let refitTimer: Timer | null = null
function refitSoon() {
  if (sidecars.size === 0) return
  refitTimer?.cancel()
  refitTimer = timeout(250, () => {
    refitTimer = null
    const f = hypr.focusedClient
    if (f && f.mapped && !f.floating && sidecars.has(f.get_monitor()?.name ?? "")) dispatch(L.layout("fit visible")).catch(console.error)
  })
}
