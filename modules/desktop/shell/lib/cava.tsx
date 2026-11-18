// The audio visualiser: each channel as a column of horizontal bars on the rail. AstalCava in
// stereo hands back left-channel bars then right-channel bars. Ambient, but driven by real
// signal (design §6).
import Cava from "gi://AstalCava"
import { setting } from "./settings"
import Gtk from "gi://Gtk?version=4.0"
import { onCleanup, type Accessor } from "ags"
import { soundRunning } from "./sound"
import Cairo from "cairo"
import { PALETTE, type Hue } from "./palette"

let inst: Cava.Cava | null | undefined
function cava() {
  if (inst === undefined) {
    inst = Cava.get_default()
    // 30 fps (sound.vizFps) is plenty for block glyphs and halves the shell's own CPU
    if (inst) {
      inst.bars = Math.max(1, setting("sound.vizBars").peek()) * 2; inst.set_stereo(true); inst.framerate = Math.min(60, Math.max(5, setting("sound.vizFps").peek()))
      // silence is not free: libcava resamples and FFTs it at 30 fps regardless (~3% of a core
      // at idle, measured). Run only while sound actually plays (lib/sound).
      const c = inst
      setting("sound.vizFps").subscribe(() => { c.framerate = Math.min(60, Math.max(5, setting("sound.vizFps").peek())) })
      setting("sound.vizBars").subscribe(() => { c.bars = Math.max(1, setting("sound.vizBars").peek()) * 2 })
      soundRunning.subscribe(() => { const want = soundRunning.peek(); if (c.active !== want) c.active = want })
      c.active = soundRunning.peek()
    }
  }
  return inst
}
// cava hands back linear amplitude, which sits low most of the time; a square root gives
// quiet passages presence without clipping loud ones
const curve = (v: number) => Math.sqrt(Math.min(1, Math.max(0, v)))
const rgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255) as [number, number, number]
const RING: Hue[] = ["amber", "pink", "lilac", "cyan", "green"]
/** the colour `t` of the way round the palette's hues (1 is back at the first), read per call
 *  as a theme change swaps them */
function ring(t: number): [number, number, number] {
  const x = (((t % 1) + 1) % 1) * RING.length, i = Math.floor(x)
  const a = rgb(PALETTE[RING[i]]), b = rgb(PALETTE[RING[(i + 1) % RING.length]])
  return a.map((v, k) => v + (b[k] - v) * (x - i)) as [number, number, number]
}

/** one channel's bars folded to `rows` bands, low freq first: each the mean of its band */
function bands(vs: number[], side: "left" | "right", rows: number): number[] {
  const n = vs.length / 2
  const ch = side === "left" ? vs.slice(0, n) : vs.slice(n)
  const step = Math.max(1, Math.floor(ch.length / rows))
  return Array.from({ length: rows }, (_, r) => ch.slice(r * step, (r + 1) * step).reduce((a, b) => a + b, 0) / step)
}

/** Both channels as bars filling its box, the bass in the middle. Redrawn only while `shown`. */
export function SpectrumBars({ shown }: { shown: Accessor<boolean> }) {
  const c = cava()
  if (!c) return <box />
  const opacity = setting("backdrop.spectrumOpacity")
  let area: Gtk.DrawingArea | null = null
  const id = c.connect("notify::values", () => { if (shown.peek()) area?.queue_draw() })
  onCleanup(() => c.disconnect(id))
  return (
    <Gtk.DrawingArea
      cssClasses={["spectrum"]}
      hexpand
      vexpand
      $={(self) => {
        area = self
        self.set_draw_func((_, cr, w, h) => {
          const vs = c.values, n = vs.length / 2
          const bars = [...vs.slice(0, n).reverse(), ...vs.slice(n)]

          const a = Math.min(1, Math.max(0.05, opacity.peek()))
          const bw = w / bars.length, mid = bars.length / 2
          bars.forEach((v, i) => {
            const bh = Math.round(curve(v) * h)
            if (bh <= 0) return
            // the palette runs outward from the bass in the middle, and each bar climbs one hue
            // further along it, foot to its own tip, so a short bar shows both colours too
            const t = (Math.abs(i + 0.5 - mid) / mid) * (1 - 1 / RING.length)
            const g = new Cairo.LinearGradient(0, h, 0, h - bh)
            g.addColorStopRGBA(0, ...ring(t), a)
            g.addColorStopRGBA(1, ...ring(t + 1 / RING.length), a)
            cr.setSource(g)
            cr.rectangle(i * bw + 1, h - bh, Math.max(1, bw - 2), bh)
            cr.fill()
          })
        })
      }}
    />
  )
}

/** One channel as a column of horizontal bars, for the rail. `rows` bars, low freq at the top.
 *  Drawn, not a label per row: 16 labels relaid out at 30 fps was most of the shell's CPU while
 *  sound played. */
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
          // the foot (the tray) falls off the bottom
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
