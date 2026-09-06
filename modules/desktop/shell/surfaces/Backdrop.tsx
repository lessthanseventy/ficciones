// The backdrop: a background-layer surface per monitor. Underneath, the photo wallpaper
// (lib/wallpaper.ts — the shell IS the wallpaper daemon, no hyprpaper); on top, when zen is on,
// a Lorenz attractor in braille with phosphor decay. `astal-shell backdrop zen|photo|toggle`.
// It earns its place purely by looking incredible (design §6).
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import { createState, onCleanup } from "ags"
import Gdk from "gi://Gdk?version=4.0"
import { interval, type Timer } from "ags/time"
import { CharGrid } from "../lib/chargrid"
import { makeModes } from "../lib/ambient"
import { wallpaper } from "../lib/wallpaper"
import Gio from "gi://Gio"
import { showText } from "./Osd"

const COLS = 210, ROWS = 64   // ≈ 1920×1200 at 9px × 18px cells
const TICK_MS = 120
const SWITCH_TICKS = Math.round(90_000 / TICK_MS)

export const [zen, setZen] = createState(false)
/** What the backdrop shows: a named ambient held, "random" (the modes rotate), or the photo. */
export const MODE_NAMES = ["lorenz", "babel", "life", "boids", "rule 30"] as const
export type BackdropMode = (typeof MODE_NAMES)[number] | "random" | "photo"
export const [backdropMode, setBackdropMode] = createState<BackdropMode>("photo")

/** One canvas per monitor: its own grid, modes, phase — neighbours never show the same thing. */
class Canvas {
  grid = new CharGrid(COLS, ROWS)
  modes = makeModes()
  idx: number
  ticks = 0
  hold = false // a named mode is held: no rotation
  // one state per row: createState skips equal strings, so a row that did not change costs
  // nothing downstream — no label reset, no Pango relayout, no overlay re-allocate (the
  // relayout of 64×210 glyphs × 2 monitors at 8 fps was the shell's idle CPU)
  rows = this.grid.lines().map((l) => createState(l))
  timer: Timer | null = null
  constructor(start: number) { this.idx = start % this.modes.length }
  step = () => {
    if (this.ticks % SWITCH_TICKS === 0 && !(this.hold && this.ticks)) {
      if (this.ticks) this.idx = (this.idx + 1) % this.modes.length
      this.modes[this.idx].init(this.grid)
    }
    this.ticks++
    const m = this.modes[this.idx]
    m.step(this.grid)
    const ls = m.text ? m.text() : this.grid.lines()
    for (let r = 0; r < ROWS; r++) this.rows[r][1](ls[r] ?? "")
  }
  /** Jump to a mode by name and hold it for a full cycle. */
  jump(name: string) {
    const i = this.modes.findIndex((m) => m.name === name)
    if (i < 0) return
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
    if (on) { this.ticks = 0; this.timer = interval(TICK_MS, this.step) }
  }
}

const canvases = new Map<Astal.Window, Canvas>()
const nexts: (() => void)[] = []
/** Skip every monitor to its next photo (the dashboard's "next wp"). */
export const nextWallpaper = () => nexts.forEach((n) => n())
let created = 0

const ORDER: BackdropMode[] = [...MODE_NAMES, "random", "photo"]
/**
 * `zen` = random rotation on, `photo` off, `toggle` between those, `cycle` (Super+Shift+Z) steps
 * through every ambient by name, then random, then the photo; a mode name holds that one.
 */
export function setBackdrop(mode: "zen" | "photo" | "toggle" | "cycle" | BackdropMode) {
  let next: BackdropMode
  if (mode === "zen") next = "random"
  else if (mode === "toggle") next = zen.get() ? "photo" : "random"
  else if (mode === "cycle") next = ORDER[(ORDER.indexOf(backdropMode.get()) + 1) % ORDER.length]
  else next = mode
  const on = next !== "photo"
  for (const [, c] of canvases) {
    if (!zen.get() || !on) c.run(on)
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
      $={(self) => { canvases.set(self, canvas); canvas.run(zen.get()); self.visible = true }}
    >
      <overlay>
        <Gtk.Picture
          contentFit={Gtk.ContentFit.COVER}
          file={file((f) => (f ? Gio.File.new_for_path(f) : null))}
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
            // clicks on the bare desktop reach the backdrop: poke whatever is running
            const g = new Gtk.GestureClick({ button: 0 })
            g.connect("pressed", (_, __, x, y) => canvas.poke(x, y, self.get_width(), self.get_height()))
            self.add_controller(g)
          }}
        >
          {canvas.rows.map(([line]) => <label cssClasses={["gl"]} useMarkup label={line} xalign={0} />)}
        </box>
        <box
          $type="overlay"
          visible={zen((z) => !z)}
          $={(self) => {
            // a click on the photo skips to the next one
            const g = new Gtk.GestureClick({ button: 0 })
            g.connect("pressed", () => next())
            self.add_controller(g)
          }}
        />
      </overlay>
    </window>
  )
}
