// The backdrop: a background-layer surface per monitor. Underneath, the photo wallpaper
// (lib/wallpaper.ts — the shell IS the wallpaper daemon, no hyprpaper); on top, when zen is on,
// a Lorenz attractor in braille with phosphor decay. `astal-shell backdrop zen|photo|toggle`.
// It earns its place purely by looking incredible (design §6).
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import { createState, onCleanup, type Accessor } from "ags"
import Gdk from "gi://Gdk?version=4.0"
import { interval, type Timer } from "ags/time"
import { CharGrid } from "../lib/chargrid"
import { makeModes, FAST_HZ, SLOW_HZ, setFastHz } from "../lib/ambient"
import { wallpaper } from "../lib/wallpaper"
import Gio from "gi://Gio"
import GLib from "gi://GLib?version=2.0"
import GObject from "gi://GObject?version=2.0"
import Graphene from "gi://Graphene?version=1.0"
import Gsk from "gi://Gsk?version=4.0"
import { showText } from "./Osd"
import { closeAny } from "./Clickaway"
import { loadHacks, haveHacks, startHack, stopHack, pauseHack } from "../lib/xscreensaver"
import { fullscreenMonitors } from "../lib/hypr"
import { setting } from "../lib/settings"

const COLS = 210, ROWS = 64   // ≈ 1920×1200 at 9px × 18px cells
setFastHz(setting("backdrop.smoothHz").peek())
const tickMs = () => 1000 / FAST_HZ
const switchTicks = () => Math.round((Math.max(10, setting("backdrop.rotateSeconds").peek()) * 1000) / tickMs())
// braille bit layout: left column bits 0,1,2,6 ; right column bits 3,4,5,7
const BITS: [number, number, number][] = [[0x01, 0, 0], [0x02, 0, 1], [0x04, 0, 2], [0x40, 0, 3], [0x08, 1, 0], [0x10, 1, 1], [0x20, 1, 2], [0x80, 1, 3]]
const DOTS_W = COLS * 2, DOTS_H = ROWS * 4

/** The dot field, drawn as GPU nodes: a cairo DrawingArea would clear and upload a
 * monitor-sized image every step (~35% of a core with an ambient up); this uploads a texel a dot. */
const DotField = GObject.registerClass(
  { GTypeName: "FiccionesDotField" },
  class DotField extends Gtk.Widget {
    paint: ((s: Gtk.Snapshot, w: number, h: number) => void) | null = null
    override vfunc_snapshot(s: Gtk.Snapshot) { this.paint?.(s, this.get_width(), this.get_height()) }
  },
)

/** Where every dot may light: each a rect 0.64 of its dot cell (the field reads quieter than
 * at 0.7), rounded to whole pixels, as alpha. Built once per size; scaled NEAREST over it, a texture of one texel per dot colours
 * each rect whole, since a rect never leaves its dot's cell. */
let mask: { w: number; h: number; tex: Gdk.Texture } | null = null
function dotMask(w: number, h: number): Gdk.Texture {
  if (mask?.w === w && mask.h === h) return mask.tex
  const dw = w / DOTS_W, dh = h / DOTS_H
  const rw = Math.max(1, Math.round(dw * 0.64)), rh = Math.max(1, Math.round(dh * 0.64))
  const ox = (dw - rw) / 2, oy = (dh - rh) / 2
  const a = new Uint8Array(w * h)
  for (let Y = 0; Y < DOTS_H; Y++) {
    const y0 = Math.round(Y * dh + oy)
    for (let X = 0; X < DOTS_W; X++) {
      const x0 = Math.round(X * dw + ox)
      for (let y = y0; y < Math.min(h, y0 + rh); y++) a.fill(255, y * w + x0, y * w + Math.min(w, x0 + rw))
    }
  }
  mask = { w, h, tex: Gdk.MemoryTexture.new(w, h, Gdk.MemoryFormat.A8, new GLib.Bytes(a), w) }
  return mask.tex
}

export const [zen, setZen] = createState(false)
/** What the backdrop shows: a named ambient held, "random" (the modes rotate), or the photo. */
export const MODE_NAMES = ["lorenz", "babel", "life", "boids", "rule 30", "pipes", "bonsai", "maze", "stars", "flow", "ant", "rain"] as const
export type BackdropMode = (typeof MODE_NAMES)[number] | "random" | "photo"
export const [backdropMode, setBackdropMode] = createState<BackdropMode>("photo")

/** One canvas per monitor: its own grid, modes, phase — neighbours never show the same thing. */
class Canvas {
  grid = new CharGrid(COLS, ROWS)
  modes = makeModes()
  idx: number
  ticks = 0
  hold = false // a named mode is held: no rotation
  paused = false // a fullscreen window covers the monitor: the tick does nothing, the mode keeps its state
  // one state per row: createState skips equal strings, so a row that did not change costs
  // nothing downstream — no label reset, no Pango relayout, no overlay re-allocate (the
  // relayout of 64×210 glyphs × 2 monitors at 8 fps was the shell's idle CPU)
  rows = this.grid.lines().map((l) => createState(l))
  timer: Timer | null = null
  /** the dot field, told to redraw each step; text modes go through the labels */
  area: Gtk.Widget | null = null
  textMode = createState(false)
  /** every other turn is an xscreensaver hack (lib/xscreensaver.ts), drawn under this window,
   * which steps aside for it; `monitor` and `win` are set once the window is up */
  hack: string | null = null
  turn = 0
  monitor: Gdk.Monitor | null = null
  win: Astal.Window | null = null
  constructor(start: number) { this.idx = start % this.modes.length; this.turn = start }
  private endHack() {
    if (this.hack && this.monitor?.connector) stopHack(this.monitor.connector)
    this.hack = null
    if (this.win) this.win.visible = true
  }
  private beginHack(): boolean {
    const m = this.monitor, g = m?.get_geometry()
    if (!m?.connector || !g || !haveHacks() || !setting("backdrop.hacks").peek()) return false
    this.hack = startHack(m.connector, g.width, g.height)
    if (this.hack && this.win) this.win.visible = false
    return !!this.hack
  }
  /** the next ambient after `i` the rotation may show; with every one switched off, simply the next */
  private nextOn(i: number) {
    const off = setting("backdrop.ambientsOff").peek(), n = this.modes.length
    for (let k = 1; k <= n; k++) if (!off.includes(this.modes[(i + k) % n].name)) return (i + k) % n
    return (i + 1) % n
  }
  setPaused(p: boolean) {
    this.paused = p
    if (this.hack && this.monitor?.connector) pauseHack(this.monitor.connector, p)
  }
  step = () => {
    if (this.paused) return
    if (this.ticks === 0 || (!this.hold && this.ticks % switchTicks() === 0)) {
      this.endHack()
      if (this.ticks) this.turn++
      if (this.turn % 2 === 1 && this.beginHack()) { this.ticks++; return }
      if (this.ticks || (!this.hold && setting("backdrop.ambientsOff").peek().includes(this.modes[this.idx].name))) this.idx = this.nextOn(this.idx)
      this.modes[this.idx].init(this.grid)
    }
    this.ticks++
    if (this.hack) return
    const m = this.modes[this.idx]
    if (!m.smooth && (this.ticks - 1) % (FAST_HZ / SLOW_HZ)) return
    m.step(this.grid)
    // a text mode (babel) is glyphs and goes through Pango; a dot mode is drawn straight onto
    // the dot field — 64 rows × 210 glyphs of colour-span markup relaid out 8× a second per
    // monitor was ~35% of a core
    const text = !!m.text
    if (this.textMode[0].peek() !== text) this.textMode[1](text)
    if (text) {
      const ls = m.text!()
      for (let r = 0; r < ROWS; r++) this.rows[r][1](ls[r] ?? "")
    } else this.area?.queue_draw()
  }
  /** one texel per dot, its hue or clear; reused frame to frame */
  private texels = new Uint32Array(DOTS_W * DOTS_H)
  /** the dot field: the dot mask (dotMask) over this step's texels, both scaled NEAREST */
  paint = (s: Gtk.Snapshot, w: number, h: number) => {
    if (!w || !h) return
    const g = this.grid, px = this.texels
    px.fill(0)
    const rgba = new Map<number, number>()
    for (let i = 0; i < g.dots.length; i++) {
      const d = g.dots[i]
      if (!d) continue
      let c = rgba.get(g.hue[i])
      if (c === undefined) {
        const x = g.colour(g.hue[i]).replace("#", "")
        // R8G8B8A8 bytes as a little-endian word
        c = (0xff000000 | (parseInt(x.slice(4, 6), 16) << 16) | (parseInt(x.slice(2, 4), 16) << 8) | parseInt(x.slice(0, 2), 16)) >>> 0
        rgba.set(g.hue[i], c)
      }
      const r = (i / COLS) | 0, at = r * 4 * DOTS_W + (i - r * COLS) * 2
      for (const [bit, dx, dy] of BITS) if (d & bit) px[at + dy * DOTS_W + dx] = c
    }
    const field = Gdk.MemoryTexture.new(DOTS_W, DOTS_H, Gdk.MemoryFormat.R8G8B8A8, new GLib.Bytes(new Uint8Array(px.buffer)), DOTS_W * 4)
    const bounds = new Graphene.Rect().init(0, 0, w, h)
    s.push_mask(Gsk.MaskMode.ALPHA)
    s.append_scaled_texture(dotMask(w, h), Gsk.ScalingFilter.NEAREST, bounds)
    s.pop()
    s.append_scaled_texture(field, Gsk.ScalingFilter.NEAREST, bounds)
    s.pop()
  }
  /** Jump to a mode by name and hold it for a full cycle. */
  jump(name: string) {
    const i = this.modes.findIndex((m) => m.name === name)
    if (i < 0) return
    this.endHack()
    this.idx = i
    this.ticks = 1
    this.modes[i].init(this.grid)
  }
  /** a click on the desktop, in widget px → dot coordinates */
  poke(px: number, py: number, w: number, h: number) {
    this.modes[this.idx].poke?.(this.grid, (px / w) * COLS * 2, (py / h) * ROWS * 4)
  }
  run(on: boolean) {
    this.timer?.cancel(); this.timer = null
    this.endHack()
    if (on) { this.ticks = 0; this.timer = interval(tickMs(), this.step) }
  }
}

const canvases = new Map<Astal.Window, Canvas>()
const nexts: (() => void)[] = []
/** Skip every monitor to its next photo (the dashboard's "next wp"). */
export const nextWallpaper = () => nexts.forEach((n) => n())
let created = 0
// the list comes after the first frames: a monitor already on a hack's turn starts that turn over
void loadHacks().then(() => { for (const c of canvases.values()) if (c.timer && !c.hack && c.turn % 2 === 1) c.ticks = 0 })
// a hack or an ambient switched off while it is up ends its turn now, not at the next rotation
// (a held ambient stays: holding it was the explicit ask)
const offNow = () => {
  const hacksOn = setting("backdrop.hacks").peek(), hacksOff = setting("backdrop.hacksOff").peek()
  const ambientsOff = setting("backdrop.ambientsOff").peek()
  for (const c of canvases.values()) {
    if (!c.timer) continue
    if (c.hack ? !hacksOn || hacksOff.includes(c.hack) : !c.hold && ambientsOff.includes(c.modes[c.idx].name)) c.ticks = 0
  }
}
// the new rate re-times every running canvas; the step counter carries on
setting("backdrop.smoothHz").subscribe(() => {
  setFastHz(setting("backdrop.smoothHz").peek())
  for (const c of canvases.values()) if (c.timer) { c.timer.cancel(); c.timer = interval(tickMs(), c.step) }
})
for (const k of ["backdrop.hacks", "backdrop.hacksOff", "backdrop.ambientsOff"] as const) setting(k).subscribe(offNow)

const ORDER: BackdropMode[] = [...MODE_NAMES, "random", "photo"]
/**
 * `zen` = random rotation on, `photo` off, `toggle` between those, `cycle` (Super+Shift+Z) steps
 * through every ambient by name, then random, then the photo; a mode name holds that one.
 */
export function setBackdrop(mode: "zen" | "photo" | "toggle" | "cycle" | BackdropMode) {
  let next: BackdropMode
  if (mode === "zen") next = "random"
  else if (mode === "toggle") next = zen.peek() ? "photo" : "random"
  else if (mode === "cycle") next = ORDER[(ORDER.indexOf(backdropMode.peek()) + 1) % ORDER.length]
  else next = mode
  const on = next !== "photo"
  for (const [, c] of canvases) {
    if (!zen.peek() || !on) c.run(on)
    c.hold = on && next !== "random"
    if (c.hold) c.jump(next)
  }
  setZen(on)
  setBackdropMode(next)
  if (mode === "cycle") showText("\u{f0e2a}  BACKDROP", next === "random" ? "random — the ambients rotate" : next === "photo" ? "photo" : next)
}

export default function Backdrop({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  const canvas = new Canvas(created++)
  const { file, next } = wallpaper()
  nexts.push(next)
  onCleanup(() => { for (const [w, c] of canvases) if (c === canvas) { c.run(false); canvases.delete(w); w.destroy() } })
  canvas.monitor = gdkmonitor
  const covered = () => canvas.setPaused(fullscreenMonitors.peek().has(gdkmonitor.connector ?? ""))
  covered()
  onCleanup(fullscreenMonitors.subscribe(covered))
  return (
    <window
      // layer/anchor BEFORE visible: gtk4-layer-shell fixes the level at map time, and a
      // `visible` prop that comes first maps the window on the default (TOP) level for good.
      cssClasses={["backdrop"]}
      namespace="astal-shell-backdrop"
      name={`backdrop-${gdkmonitor.connector}`}
      gdkmonitor={gdkmonitor}
      layer={Astal.Layer.BACKGROUND}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM}
      application={app}
      $={(self) => { canvases.set(self, canvas); canvas.win = self; canvas.run(zen.peek()); self.visible = true }}
    >
      <overlay>
        <Gtk.Picture
          contentFit={Gtk.ContentFit.COVER}
          file={file((f) => (f ? Gio.File.new_for_path(f) : null)) as unknown as Accessor<Gio.File>}
          visible={zen((z) => !z)}
        />
        <box
          $type="overlay"
          orientation={Gtk.Orientation.VERTICAL}
          cssClasses={["grid"]}
          halign={Gtk.Align.CENTER}
          valign={Gtk.Align.CENTER}
          visible={zen}
          $={(self) => {
            // clicks on the bare desktop reach the backdrop: close what's open, poke whatever is running
            // any button, deliberately: every other gesture is primary-only
            const g = new Gtk.GestureClick({ button: 0 })
            g.connect("pressed", (_, __, x, y) => { closeAny(); canvas.poke(x, y, self.get_width(), self.get_height()) })
            self.add_controller(g)
          }}
        >
          <box orientation={Gtk.Orientation.VERTICAL} visible={canvas.textMode[0]}>
            {canvas.rows.map(([line]) => <label cssClasses={["gl"]} useMarkup label={line} xalign={0} />)}
          </box>
          <DotField
            visible={canvas.textMode[0]((t) => !t)}
            widthRequest={COLS * 9}
            heightRequest={ROWS * 18}
            $={(self) => { canvas.area = self; self.paint = canvas.paint }}
          />
        </box>
        <box
          $type="overlay"
          visible={zen((z) => !z)}
          $={(self) => {
            // a click on the photo closes what's open, and skips to the next one
            const g = new Gtk.GestureClick({ button: 0 })
            g.connect("pressed", () => { closeAny(); next() })
            self.add_controller(g)
          }}
        />
      </overlay>
    </window>
  )
}
