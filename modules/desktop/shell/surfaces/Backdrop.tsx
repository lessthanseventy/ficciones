// The zen backdrop: a background-layer surface drawing a Lorenz attractor in braille with
// phosphor decay, in place of the photo wallpaper. `astal-shell backdrop zen|photo|toggle`.
// It earns its place purely by looking incredible (design §6).
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import { createState, For } from "ags"
import { interval, type Timer } from "ags/time"
import { CharGrid } from "../lib/chargrid"

const COLS = 210, ROWS = 64   // ≈ 1920×1200 at 9px × 18px cells
const grid = new CharGrid(COLS, ROWS)
const [lines, setLines] = createState<string[]>(grid.lines())
let win: Astal.Window | null = null
let timer: Timer | null = null
export const [zen, setZen] = createState(false)

// Lorenz: σ=10, ρ=28, β=8/3; three tracers so the wings fill quickly
const tracers = [{ x: 0.1, y: 0, z: 0 }, { x: -0.2, y: 0.1, z: 20 }, { x: 8, y: 8, z: 27 }]
function step() {
  grid.decay(0.045)
  for (const t of tracers) {
    for (let i = 0; i < 40; i++) {
      const dt = 0.004
      const dx = 10 * (t.y - t.x), dy = t.x * (28 - t.z) - t.y, dz = t.x * t.y - (8 / 3) * t.z
      t.x += dx * dt; t.y += dy * dt; t.z += dz * dt
      // project x–z onto the dot canvas
      grid.plot((t.x + 24) / 48 * COLS * 2, (1 - (t.z - 2) / 50) * ROWS * 4)
    }
  }
  setLines(grid.lines())
}

export function setBackdrop(mode: "zen" | "photo" | "toggle") {
  if (!win) return
  const on = mode === "toggle" ? !win.visible : mode === "zen"
  win.visible = on
  setZen(on)
  timer?.cancel(); timer = null
  if (on) timer = interval(80, step)
}

export default function Backdrop() {
  return (
    <window
      $={(self) => (win = self)}
      visible={false}
      cssClasses={["backdrop"]}
      namespace="astal-shell-backdrop"
      name="backdrop"
      layer={Astal.Layer.BACKGROUND}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM}
      application={app}
    >
      <box orientation={Gtk.Orientation.VERTICAL} cssClasses={["grid"]} halign={Gtk.Align.CENTER} valign={Gtk.Align.CENTER}>
        {Array.from({ length: ROWS }, (_, r) => <label cssClasses={["gl"]} label={lines((l) => l[r] ?? "")} xalign={0} />)}
      </box>
    </window>
  )
}
