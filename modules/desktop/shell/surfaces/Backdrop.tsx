// The zen backdrop: a background-layer surface drawing a Lorenz attractor in braille with
// phosphor decay, in place of the photo wallpaper. `astal-shell backdrop zen|photo|toggle`.
// It earns its place purely by looking incredible (design §6).
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import { createState, onCleanup } from "ags"
import Gdk from "gi://Gdk?version=4.0"
import { interval, type Timer } from "ags/time"
import { CharGrid } from "../lib/chargrid"
import { makeModes } from "../lib/ambient"

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
  run(on: boolean) {
    this.timer?.cancel(); this.timer = null
    if (on) { this.ticks = 0; this.timer = interval(TICK_MS, this.step) }
  }
}

const canvases = new Map<Astal.Window, Canvas>()
let created = 0

export function setBackdrop(mode: "zen" | "photo" | "toggle") {
  const on = mode === "toggle" ? !zen.get() : mode === "zen"
  for (const [w, c] of canvases) { w.visible = on; c.run(on) }
  setZen(on)
}

export default function Backdrop({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  const canvas = new Canvas(created++)
  const [lines] = canvas.lines
  onCleanup(() => { for (const [w, c] of canvases) if (c === canvas) { c.run(false); canvases.delete(w); w.destroy() } })
  return (
    <window
      $={(self) => { canvases.set(self, canvas); self.visible = zen.get(); canvas.run(zen.get()) }}
      visible={false}
      cssClasses={["backdrop"]}
      namespace="astal-shell-backdrop"
      name={`backdrop-${gdkmonitor.connector}`}
      gdkmonitor={gdkmonitor}
      layer={Astal.Layer.BACKGROUND}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM}
      application={app}
    >
      <box orientation={Gtk.Orientation.VERTICAL} cssClasses={["grid"]} halign={Gtk.Align.CENTER} valign={Gtk.Align.CENTER}>
        {Array.from({ length: ROWS }, (_, r) => <label cssClasses={["gl"]} useMarkup label={lines((l) => l[r] ?? "")} xalign={0} />)}
      </box>
    </window>
  )
}
