// The audio visualiser: AstalCava's bars as block glyphs, in the bar's open middle. Ambient,
// but driven by real signal (design §6) — silence is a flat line of the lowest glyph.
import Cava from "gi://AstalCava"
import { createBinding } from "ags"

const BLOCKS = "▁▂▃▄▅▆▇█"
const BARS = 28

export function Visualiser() {
  const cava = Cava.get_default()
  if (!cava) return <label cssClasses={["cava", "dim"]} label="" />
  cava.bars = BARS
  const line = createBinding(cava, "values")((vs) =>
    vs.map((v) => BLOCKS[Math.min(7, Math.max(0, Math.round(v * 7)))]).join(""),
  )
  return <label cssClasses={["cava"]} label={line} />
}
