// WEATHER: the card is where the depth lives — now with feels-like, humidity, wind and UV;
// the next hours as a strip; five days with rain chance; sunrise and sunset. open-meteo.
import Gtk from "gi://Gtk?version=4.0"
import { weather, glyph, type Hour, type Day } from "../lib/weather"
import { RuleH } from "../lib/tui"

const hh = (ms: number) => {
  const h = new Date(ms).getHours()
  return `${h % 12 || 12}${h < 12 ? "a" : "p"}`
}
const dow = (ms: number, i: number) => (i === 0 ? "today" : new Date(ms).toLocaleDateString([], { weekday: "short" }).toLowerCase())
const clock = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }).toLowerCase().replace(" ", "")

function Now() {
  const big = weather((w) => (w.ok ? `${Math.round(w.temp!)}°` : "—"))
  const g = weather((w) => (w.ok ? glyph(w.code) : "\u{f0590}"))
  const l1 = weather((w) => (w.ok ? `feels ${Math.round(w.feels ?? w.temp!)}°  ·  ${Math.round(w.low!)}° – ${Math.round(w.high!)}°` : w.note ?? ""))
  const l2 = weather((w) => (w.ok ? `humidity ${w.humidity}%  ·  wind ${Math.round(w.wind!)} mph  ·  uv ${Math.round(w.days?.[0]?.uv ?? 0)}` : ""))
  const l3 = weather((w) => (w.ok && w.days?.[0] ? `\u{f059b} ${clock(w.days[0].sunrise)}   \u{f059a} ${clock(w.days[0].sunset)}` : ""))
  return (
    <box spacing={14}>
      <label cssClasses={["wx-glyph"]} label={g} valign={Gtk.Align.START} />
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2} hexpand>
        <label cssClasses={["huge"]} label={big} xalign={0} />
        <label label={l1} xalign={0} />
        <label cssClasses={["dim", "sm"]} label={l2} xalign={0} />
        <label cssClasses={["dim", "sm"]} label={l3} xalign={0} />
      </box>
    </box>
  )
}

/** The next hours, every two, as columns: hour / sky / temp / rain chance. The temp carries a
 * leading space so the digits sit centred despite the degree sign. */
function Hours() {
  const cols = weather((w) => (w.hours ?? []).filter((_, i) => i % 2 === 0).slice(0, 8))
  return (
    <box cssClasses={["hours"]}>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={1} cssClasses={["hours-key"]}>
        <label cssClasses={["k", "sm"]} label={"\u{f0150}"} />
        <label cssClasses={["sky", "k"]} label={"\u{f0590}"} />
        <label cssClasses={["k"]} label={"\u{f050f}"} />
        <label cssClasses={["k", "sm"]} label={"\u{f0597}"} />
      </box>
      <box homogeneous hexpand>
      {Array.from({ length: 8 }, (_, i) => (
        <box orientation={Gtk.Orientation.VERTICAL} spacing={1} visible={cols((c) => i < c.length)}>
          <label cssClasses={["dim", "sm"]} label={cols((c) => (c[i] ? hh(c[i].t) : ""))} />
          <label cssClasses={["sky"]} label={cols((c) => (c[i] ? glyph(c[i].code) : ""))} />
          <label label={cols((c) => (c[i] ? ` ${Math.round(c[i].temp)}°` : ""))} />
          <label cssClasses={cols((c) => ["sm", (c[i]?.rain ?? 0) >= 30 ? "cyan" : "dim"])} label={cols((c) => (c[i] ? `${c[i].rain}%` : ""))} />
        </box>
      ))}
      </box>
    </box>
  )
}

/** Five days: day / sky / low–high with a bar spanning the week's range / rain chance. */
function Days() {
  const days = weather((w) => (w.days ?? []).slice(0, 6))
  const range = days((d) => ({ lo: Math.min(...d.map((x) => x.low), 999), hi: Math.max(...d.map((x) => x.high), -999) }))
  // the week's range is the track (dim); the day's span sits on it (amber)
  const seg = (d: Day, r: { lo: number; hi: number }): [number, number] => {
    const W = 12
    const span = Math.max(1, r.hi - r.lo)
    const a = Math.round(((d.low - r.lo) / span) * W)
    const b = Math.max(a + 1, Math.round(((d.high - r.lo) / span) * W))
    return [a, b]
  }
  const part = (i: number, which: 0 | 1 | 2) =>
    days((d) => {
      if (!d[i]) return ""
      const [a, b] = seg(d[i], range.get())
      return which === 0 ? "─".repeat(a) : which === 1 ? "━".repeat(b - a) : "─".repeat(12 - b)
    })
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      {Array.from({ length: 6 }, (_, i) => (
        <box cssClasses={["day"]} spacing={8} visible={days((d) => i < d.length)}>
          <label cssClasses={["dim"]} label={days((d) => (d[i] ? dow(d[i].t, i) : ""))} widthChars={5} xalign={0} />
          <label cssClasses={["sky"]} label={days((d) => (d[i] ? glyph(d[i].code) : ""))} />
          <label cssClasses={["dim"]} label={days((d) => (d[i] ? `${Math.round(d[i].low)}°` : ""))} widthChars={4} xalign={1} />
          <box cssClasses={["range"]}>
            <label cssClasses={["track"]} label={part(i, 0)} />
            <label cssClasses={["span"]} label={part(i, 1)} />
            <label cssClasses={["track"]} label={part(i, 2)} />
          </box>
          <label cssClasses={["amber"]} label={days((d) => (d[i] ? `${Math.round(d[i].high)}°` : ""))} widthChars={4} xalign={0} />
          <label cssClasses={days((d) => ["sm", (d[i]?.rain ?? 0) >= 30 ? "cyan" : "dim"])} label={days((d) => (d[i] && d[i].rain > 0 ? `\u{f0597} ${d[i].rain}%` : ""))} hexpand xalign={1} />
        </box>
      ))}
    </box>
  )
}

export function WeatherCard() {
  const stale = weather((w) => (w.note === "stale" ? "stale — network down" : ""))
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={8}>
      <Now />
      <RuleH />
      <Hours />
      <RuleH />
      <Days />
      <label cssClasses={["red", "sm"]} label={stale} xalign={0} visible={stale((n) => !!n)} />
    </box>
  )
}
