// The audio visualiser: each channel as a column of horizontal bars on the rail. AstalCava in
// stereo hands back left-channel bars then right-channel bars. Ambient, but driven by real
// signal (design §6).
import Cava from "gi://AstalCava"
import { setting } from "./settings"
import Gtk from "gi://Gtk?version=4.0"
import { onCleanup } from "ags"
import { soundRunning } from "./sound"

const BARS = 24 // per channel

let inst: Cava.Cava | null | undefined
function cava() {
  if (inst === undefined) {
    inst = Cava.get_default()
    // 30 fps (sound.vizFps) is plenty for block glyphs and halves the shell's own CPU
    if (inst) {
      inst.bars = BARS * 2; inst.set_stereo(true); inst.framerate = setting("sound.vizFps").peek()
      // silence is not free: libcava resamples and FFTs it at 30 fps regardless (~3% of a core
      // at idle, measured). Run only while sound actually plays (lib/sound).
      const c = inst
      setting("sound.vizFps").subscribe(() => { c.framerate = Math.min(60, Math.max(5, setting("sound.vizFps").peek())) })
      soundRunning.subscribe(() => { const want = soundRunning.peek(); if (c.active !== want) c.active = want })
      c.active = soundRunning.peek()
    }
  }
  return inst
}
// cava hands back linear amplitude, which sits low most of the time; a square root gives
// quiet passages presence without clipping loud ones
const curve = (v: number) => Math.sqrt(Math.min(1, Math.max(0, v)))

/** one channel's bars folded to `rows` bands, low freq first: each the mean of its band */
function bands(vs: number[], side: "left" | "right", rows: number): number[] {
  const n = vs.length / 2
  const ch = side === "left" ? vs.slice(0, n) : vs.slice(n)
  const step = Math.max(1, Math.floor(ch.length / rows))
  return Array.from({ length: rows }, (_, r) => ch.slice(r * step, (r + 1) * step).reduce((a, b) => a + b, 0) / step)
}

/** One channel as a column of horizontal bars, for the rail. `rows` bars, low freq at the top.
 *  Drawn, not a label per row: 16 labels relaid out at 30 fps was most of the shell's CPU while
 *  sound played (2026-09-11). */
export function Channel({ side, rows = 8 }: { side: "left" | "right"; rows?: number }) {
  const c = cava()
  if (!c) return <box />
  const W = 36
  let vals: number[] = []
  let area: Gtk.DrawingArea | null = null
  const id = c.connect("notify::values", () => { vals = bands(c.values, side, rows); area?.queue_draw() })
  onCleanup(() => c.disconnect(id))
  return (
    <box cssClasses={["cava-col", side]} widthRequest={W} halign={Gtk.Align.START}>
      <Gtk.DrawingArea
        cssClasses={["ch"]}
        widthRequest={W}
        $={(self) => {
          area = self
          // a full bar is four block glyphs wide, as the labels drew it; a row is 15px, not the
          // font's 18px line box — at 18 the rail's three sections overrun a 1080 monitor and
          // the foot (the tray) falls off the bottom (2026-09-18)
          const [gw] = self.create_pango_layout("█").get_pixel_size()
          const rowH = 15
          self.heightRequest = rows * rowH
          self.set_draw_func((_, cr, w) => {
            const col = self.get_color()
            cr.setSourceRGBA(col.red, col.green, col.blue, col.alpha)
            const full = Math.min(w, 4 * gw)
            vals.forEach((v, r) => { const bw = Math.round(curve(v) * full); if (bw > 0) cr.rectangle(0, r * rowH, bw, rowH - 1) })
            cr.fill()
          })
        }}
      />
    </box>
  )
}
