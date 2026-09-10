// The audio visualiser. AstalCava in stereo hands back left-channel bars then right-channel
// bars; the bar shows the mix as vertical blocks, the rail shows each channel as a stack of
// horizontal blocks. Ambient, but driven by real signal (design §6).
import Cava from "gi://AstalCava"
import Gtk from "gi://Gtk?version=4.0"
import { createBinding } from "ags"
import { soundRunning } from "./sound"

const V = "▁▂▃▄▅▆▇█"
const H = "▏▎▍▌▋▊▉█"
const BARS = 24 // per channel

let inst: Cava.Cava | null | undefined
function cava() {
  if (inst === undefined) {
    inst = Cava.get_default()
    // 30 fps is plenty for block glyphs and halves the shell's own CPU
    if (inst) {
      inst.bars = BARS * 2; inst.set_stereo(true); inst.framerate = 30
      // silence is not free: libcava resamples and FFTs it at 30 fps regardless (~3% of a core
      // at idle, measured). Run only while sound actually plays (lib/sound).
      const c = inst
      soundRunning.subscribe(() => { const want = soundRunning.peek(); if (c.active !== want) c.active = want })
      c.active = soundRunning.peek()
    }
  }
  return inst
}
// cava hands back linear amplitude, which sits low most of the time; a square root gives
// quiet passages presence without clipping loud ones
const curve = (v: number) => Math.sqrt(Math.min(1, Math.max(0, v)))
const level = (v: number) => Math.min(7, Math.round(curve(v) * 7))

/** Both channels mixed, left to right, for the bar. */
export function Visualiser() {
  const c = cava()
  if (!c) return <label cssClasses={["cava"]} label="" />
  const line = createBinding(c, "values")((vs) => {
    const n = vs.length / 2
    return Array.from({ length: n }, (_, i) => V[level((vs[i] + vs[n + i]) / 2)]).join("")
  })
  // fixed glyph count so the cell never resizes with the signal
  return <label cssClasses={["cava"]} label={line} widthChars={BARS} maxWidthChars={BARS} />
}

const COLS = 4 // cells per row: full blocks + one fractional block, 32 levels

/** A horizontal bar of `cols` cells: full blocks then a partial, grown from the left. */
function hbar(v: number, cols = COLS): string {
  const eighths = Math.round(curve(v) * cols * 8)
  const full = Math.floor(eighths / 8)
  const rest = eighths % 8
  return "█".repeat(full) + (rest ? H[rest - 1] : "")
}

/** One channel as a column of horizontal bars, for the rail. `rows` bars, low freq at the top. */
export function Channel({ side, rows = 8 }: { side: "left" | "right"; rows?: number }) {
  const c = cava()
  if (!c) return <box />
  const lines = createBinding(c, "values")((vs) => {
    const n = vs.length / 2
    const ch = side === "left" ? vs.slice(0, n) : vs.slice(n)
    const step = Math.max(1, Math.floor(ch.length / rows))
    return Array.from({ length: rows }, (_, r) => {
      const v = ch.slice(r * step, (r + 1) * step).reduce((a, b) => a + b, 0) / step
      return hbar(v)
    })
  })
  // block glyphs are wider than a mono cell, so the column is clipped to a fixed width — a
  // full row must never widen the rail
  const W = 36
  return (
    <scrolledwindow
      cssClasses={["cava-col", side]}
      hscrollbarPolicy={Gtk.PolicyType.EXTERNAL}
      vscrollbarPolicy={Gtk.PolicyType.NEVER}
      widthRequest={W}
      maxContentWidth={W}
      halign={Gtk.Align.START}
    >
      <box orientation={Gtk.Orientation.VERTICAL}>
        {Array.from({ length: rows }, (_, r) => (
          <label cssClasses={["ch"]} label={lines((l) => l[r])} xalign={0} />
        ))}
      </box>
    </scrolledwindow>
  )
}
