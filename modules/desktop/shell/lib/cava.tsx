// The audio visualiser. AstalCava in stereo hands back left-channel bars then right-channel
// bars; the bar shows the mix as vertical blocks, the rail shows each channel as a stack of
// horizontal blocks. Ambient, but driven by real signal (design §6).
import Cava from "gi://AstalCava"
import Gtk from "gi://Gtk?version=4.0"
import { createBinding } from "ags"

const V = "▁▂▃▄▅▆▇█"
const H = "▏▎▍▌▋▊▉█"
const BARS = 24 // per channel

let inst: Cava.Cava | null | undefined
function cava() {
  if (inst === undefined) {
    inst = Cava.get_default()
    if (inst) { inst.bars = BARS * 2; inst.set_stereo(true) }
  }
  return inst
}
const level = (v: number) => Math.min(7, Math.max(0, Math.round(v * 7)))

/** Both channels mixed, left to right, for the bar. */
export function Visualiser() {
  const c = cava()
  if (!c) return <label cssClasses={["cava"]} label="" />
  const line = createBinding(c, "values")((vs) => {
    const n = vs.length / 2
    return Array.from({ length: n }, (_, i) => V[level((vs[i] + vs[n + i]) / 2)]).join("")
  })
  return <label cssClasses={["cava"]} label={line} />
}

/** One channel as a column of horizontal blocks, for the rail. `rows` bars, low freq at the top. */
export function Channel({ side, rows = 8 }: { side: "left" | "right"; rows?: number }) {
  const c = cava()
  if (!c) return <box />
  const lines = createBinding(c, "values")((vs) => {
    const n = vs.length / 2
    const ch = side === "left" ? vs.slice(0, n) : vs.slice(n)
    const step = Math.max(1, Math.floor(ch.length / rows))
    return Array.from({ length: rows }, (_, r) => {
      const v = ch.slice(r * step, (r + 1) * step).reduce((a, b) => a + b, 0) / step
      return H[level(v)]
    })
  })
  return (
    <box cssClasses={["cava-col", side]} orientation={Gtk.Orientation.VERTICAL} halign={Gtk.Align.CENTER}>
      {Array.from({ length: rows }, (_, r) => (
        <label cssClasses={["ch"]} label={lines((l) => l[r])} xalign={side === "left" ? 0 : 1} widthChars={4} />
      ))}
    </box>
  )
}
