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

const COLS = 210, ROWS = 64   // ≈ 1920×1200 at 9px × 18px cells
const TICK_MS = 120
const SWITCH_TICKS = Math.round(90_000 / TICK_MS)

export const [zen, setZen] = createState(false)

/** One canvas per monitor: its own grid, modes, phase — neighbours never show the same thing. */
class Canvas {
  grid = new CharGrid(COLS, ROWS)
  modes = makeModes()
  idx: number
  ticks = 0
  lines = createState<string[]>(this.grid.lines())
  timer: Timer | null = null
  constructor(start: number) { this.idx = start % this.modes.length }
  step = () => {
    if (this.ticks % SWITCH_TICKS === 0) {
      if (this.ticks) this.idx = (this.idx + 1) % this.modes.length
      this.modes[this.idx].init(this.grid)
    }
    this.ticks++
    this.modes[this.idx].step(this.grid)
    this.lines[1](this.grid.lines())
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
let created = 0

export function setBackdrop(mode: "zen" | "photo" | "toggle") {
  const on = mode === "toggle" ? !zen.get() : mode === "zen"
  for (const [, c] of canvases) c.run(on)
  setZen(on)
}

export default function Backdrop({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  const canvas = new Canvas(created++)
  const [lines] = canvas.lines
  const { file, next } = wallpaper()
  onCleanup(() => { for (const [w, c] of canvases) if (c === canvas) { c.run(false); canvases.delete(w); w.destroy() } })
  return (
    <window
      $={(self) => { canvases.set(self, canvas); canvas.run(zen.get()) }}
      visible
      cssClasses={["backdrop"]}
      namespace="astal-shell-backdrop"
      name={`backdrop-${gdkmonitor.connector}`}
      gdkmonitor={gdkmonitor}
      layer={Astal.Layer.BACKGROUND}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM}
      application={app}
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
          {Array.from({ length: ROWS }, (_, r) => <label cssClasses={["gl"]} useMarkup label={lines((l) => l[r] ?? "")} xalign={0} />)}
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
