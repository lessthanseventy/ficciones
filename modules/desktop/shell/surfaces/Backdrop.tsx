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
import { makeModes, FAST_HZ, SLOW_HZ } from "../lib/ambient"
import { wallpaper } from "../lib/wallpaper"
import Gio from "gi://Gio"
import Cairo from "cairo"
import { showText } from "./Osd"
import { closeAny } from "./Clickaway"
import { loadHacks, haveHacks, startHack, stopHack, pauseHack } from "../lib/xscreensaver"
import { fullscreenMonitors } from "../lib/hypr"

const COLS = 210, ROWS = 64   // ≈ 1920×1200 at 9px × 18px cells
const TICK_MS = 1000 / FAST_HZ
const SWITCH_TICKS = Math.round(90_000 / TICK_MS)
// braille bit layout: left column bits 0,1,2,6 ; right column bits 3,4,5,7
const BITS: [number, number, number][] = [[0x01, 0, 0], [0x02, 0, 1], [0x04, 0, 2], [0x40, 0, 3], [0x08, 1, 0], [0x10, 1, 1], [0x20, 1, 2], [0x80, 1, 3]]

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
  /** the dot canvas (cairo), told to redraw each step; text modes go through the labels */
  area: Gtk.DrawingArea | null = null
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
    if (!m?.connector || !g || !haveHacks()) return false
    this.hack = startHack(m.connector, g.width, g.height)
    if (this.hack && this.win) this.win.visible = false
    return !!this.hack
  }
  setPaused(p: boolean) {
    this.paused = p
    if (this.hack && this.monitor?.connector) pauseHack(this.monitor.connector, p)
  }
  step = () => {
    if (this.paused) return
    if (this.ticks % SWITCH_TICKS === 0 && !(this.hold && this.ticks)) {
      this.endHack()
      if (this.ticks) this.turn++
      if (this.turn % 2 === 1 && this.beginHack()) { this.ticks++; return }
      if (this.ticks) this.idx = (this.idx + 1) % this.modes.length
      this.modes[this.idx].init(this.grid)
    }
    this.ticks++
    if (this.hack) return
    const m = this.modes[this.idx]
    if (!m.smooth && (this.ticks - 1) % (FAST_HZ / SLOW_HZ)) return
    m.step(this.grid)
    // a text mode (babel) is glyphs and goes through Pango; a dot mode is drawn straight onto
    // the canvas — 64 rows × 210 glyphs of colour-span markup relaid out 8× a second per
    // monitor was ~35% of a core (2026-09-07); the same dots as cairo rects is a few ms
    const text = !!m.text
    if (this.textMode[0].peek() !== text) this.textMode[1](text)
    if (text) {
      const ls = m.text!()
      for (let r = 0; r < ROWS; r++) this.rows[r][1](ls[r] ?? "")
    } else this.area?.queue_draw()
  }
  /** the dot field: every lit dot a small rect in its cell's hue. One fill per hue (≤5), not
   * one per cell — 13k fills a frame was most of the cost; no antialiasing on the dots. Lit
   * cells are bucketed by hue in one pass (five full-grid scans before, 2026-09-11). */
  draw = (_: Gtk.DrawingArea, cr: Cairo.Context, w: number, h: number) => {
    const g = this.grid
    const cw = w / COLS, ch = h / ROWS, dw = cw / 2, dh = ch / 4
    // 0.64 of a dot's cell (0.7 first): the field reads ~10% quieter
    const rw = Math.max(1, Math.round(dw * 0.64)), rh = Math.max(1, Math.round(dh * 0.64))
    const ox = (dw - rw) / 2, oy = (dh - rh) / 2
    cr.setAntialias(Cairo.Antialias.NONE)
    const byHue = new Map<number, number[]>()
    for (let i = 0; i < g.dots.length; i++) {
      if (!g.dots[i]) continue
      let cells = byHue.get(g.hue[i])
      if (!cells) byHue.set(g.hue[i], (cells = []))
      cells.push(i)
    }
    for (const [hue, cells] of byHue) {
      const x = g.colour(hue).replace("#", "")
      cr.setSourceRGB(parseInt(x.slice(0, 2), 16) / 255, parseInt(x.slice(2, 4), 16) / 255, parseInt(x.slice(4, 6), 16) / 255)
      for (const i of cells) {
        const r = (i / COLS) | 0, x0 = (i - r * COLS) * cw, y0 = r * ch, d = g.dots[i]
        for (const [bit, dx, dy] of BITS) if (d & bit) cr.rectangle(Math.round(x0 + dx * dw + ox), Math.round(y0 + dy * dh + oy), rw, rh)
      }
      cr.fill()
    }
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
    if (on) { this.ticks = 0; this.timer = interval(TICK_MS, this.step) }
  }
}

const canvases = new Map<Astal.Window, Canvas>()
const nexts: (() => void)[] = []
/** Skip every monitor to its next photo (the dashboard's "next wp"). */
export const nextWallpaper = () => nexts.forEach((n) => n())
let created = 0
// the list comes after the first frames: a monitor already on a hack's turn starts that turn over
void loadHacks().then(() => { for (const c of canvases.values()) if (c.timer && !c.hack && c.turn % 2 === 1) c.ticks = 0 })

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
            const g = new Gtk.GestureClick({ button: 0 })
            g.connect("pressed", (_, __, x, y) => { closeAny(); canvas.poke(x, y, self.get_width(), self.get_height()) })
            self.add_controller(g)
          }}
        >
          <box orientation={Gtk.Orientation.VERTICAL} visible={canvas.textMode[0]}>
            {canvas.rows.map(([line]) => <label cssClasses={["gl"]} useMarkup label={line} xalign={0} />)}
          </box>
          <Gtk.DrawingArea
            visible={canvas.textMode[0]((t) => !t)}
            widthRequest={COLS * 9}
            heightRequest={ROWS * 18}
            $={(self) => { canvas.area = self; self.set_draw_func(canvas.draw) }}
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
