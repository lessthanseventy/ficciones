// WEATHER: the card is where the depth lives — now with feels-like, humidity, wind and UV;
// the next hours as a strip; five days with rain chance; sunrise and sunset. open-meteo.
import Gtk from "gi://Gtk?version=4.0"
import { weather, glyph, describe, type Day } from "../lib/weather"
import { RuleH } from "../lib/tui"
import Cairo from "cairo"
import { PALETTE } from "../lib/palette"

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
// The board's weather is a picture, not the popover's table again (Andrew, 2026-09-07): the next
// 24 h as two panels on one time axis — temperature as a line (its high and low labelled, and
// nothing else), rain chance as thin bars beneath — with now, sunrise and sunset marked.
// cairo, so it costs nothing at rest (drawn on data change only).
const rgb = (hex: string): [number, number, number] => { const x = hex.replace("#", ""); return [parseInt(x.slice(0, 2), 16) / 255, parseInt(x.slice(2, 4), 16) / 255, parseInt(x.slice(4, 6), 16) / 255] }
function Chart() {
  let area: Gtk.DrawingArea | null = null
  const draw = (_: Gtk.DrawingArea, cr: Cairo.Context, w: number, h: number) => {
    const wx = weather.peek()
    const hs = (wx.hours ?? []).slice(0, 24)
    if (hs.length < 2) return
    const set = (c: string) => { const [r, g, b] = rgb(c); cr.setSourceRGB(r, g, b) }
    const left = 34, right = 8, top = 10, gap = 8, rainH = 34, labelH = 16
    const tempH = h - top - gap - rainH - labelH
    const x = (i: number) => left + ((w - left - right) * i) / (hs.length - 1)
    const temps = hs.map((p) => p.temp)
    const lo = Math.min(...temps), hi = Math.max(...temps)
    const span = Math.max(4, hi - lo)
    const y = (t: number) => top + tempH - ((t - lo) / span) * tempH
    cr.selectFontFace("ComicShannsMono Nerd Font", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL)
    cr.setFontSize(11)
    // the axis: a recessive baseline and the hour labels every 3 h
    set(PALETTE.dim); cr.setLineWidth(1)
    cr.moveTo(left, top + tempH + 0.5); cr.lineTo(w - right, top + tempH + 0.5); cr.stroke()
    set(PALETTE.dim)
    for (let i = 0; i < hs.length; i += 3) { const s = hh(hs[i].t); cr.moveTo(x(i) - cr.textExtents(s).width / 2, h - 3); cr.showText(s) }
    // now, sunrise, sunset: dim uprights with a small label
    const t0 = hs[0].t, t1 = hs[hs.length - 1].t
    const xt = (ms: number) => left + ((w - left - right) * (ms - t0)) / (t1 - t0)
    const marks: [number, string][] = [[Date.now(), "now"]]
    for (const d of (wx.days ?? []).slice(0, 2)) for (const [iso, tag] of [[d.sunrise, "\u{f059c}"], [d.sunset, "\u{f059b}"]] as const) { const ms = new Date(iso).getTime(); if (ms > t0 && ms < t1) marks.push([ms, tag]) }
    for (const [ms, tag] of marks) {
      if (ms < t0 || ms > t1) continue
      const mx = Math.round(xt(ms)) + 0.5
      set(tag === "now" ? PALETTE.amber : PALETTE.dim)
      cr.setLineWidth(1); cr.moveTo(mx, top); cr.lineTo(mx, top + tempH + gap + rainH); cr.stroke()
      cr.moveTo(mx + 3, top + 9); cr.showText(tag)
    }
    // rain chance: thin cyan bars, a 2px gap between them, on their own panel
    const bw = (w - left - right) / hs.length
    const rainTop = top + tempH + gap
    set(PALETTE.cyan)
    hs.forEach((p, i) => { if (p.rain > 0) { const bh = Math.max(1, (p.rain / 100) * rainH); cr.rectangle(x(i) - bw / 2 + 1, rainTop + rainH - bh, Math.max(1, bw - 2), bh) } })
    cr.fill()
    set(PALETTE.dim); cr.moveTo(2, rainTop + rainH - 2); cr.showText("\u{f0597}")
    // temperature: the line, then its two labelled points
    set(PALETTE.amber); cr.setLineWidth(2); cr.setLineJoin(Cairo.LineJoin.ROUND)
    hs.forEach((p, i) => (i ? cr.lineTo(x(i), y(p.temp)) : cr.moveTo(x(i), y(p.temp))))
    cr.stroke()
    const iHi = temps.indexOf(hi), iLo = temps.indexOf(lo)
    for (const [i, v, above] of [[iHi, hi, true], [iLo, lo, false]] as const) {
      cr.arc(x(i), y(v), 3, 0, Math.PI * 2); cr.fill()
      const s = `${Math.round(v)}°`; const tw = cr.textExtents(s).width
      cr.moveTo(Math.min(Math.max(left, x(i) - tw / 2), w - right - tw), above ? y(v) - 7 : y(v) + 14); cr.showText(s)
    }
    // the scale: high and low on the left
    set(PALETTE.dim); cr.setFontSize(10)
    cr.moveTo(2, top + 4); cr.showText(`${Math.round(hi)}°`); cr.moveTo(2, top + tempH); cr.showText(`${Math.round(lo)}°`)
  }
  weather.subscribe(() => area?.queue_draw())
  return <Gtk.DrawingArea heightRequest={130} hexpand $={(self) => { area = self; self.set_draw_func(draw) }} />
}

function Days({ wide = false }: { wide?: boolean } = {}) {
  // the board's card is wide: its rows carry the day at a glance after the range — the sky
  // every three hours, the day's wind, rain total, sunrise and sunset (Andrew, 2026-09-07:
  // "something else instead of a super wide bar")
  const W = wide ? 20 : 8
  const days = weather((w) => (w.days ?? []).slice(0, 6))
  const range = days((d) => ({ lo: Math.min(...d.map((x) => x.low), 999), hi: Math.max(...d.map((x) => x.high), -999) }))
  // the week's range is the track (dim); the day's span sits on it (amber)
  const seg = (d: Day, r: { lo: number; hi: number }): [number, number] => {
    const span = Math.max(1, r.hi - r.lo)
    const a = Math.round(((d.low - r.lo) / span) * W)
    const b = Math.max(a + 1, Math.round(((d.high - r.lo) / span) * W))
    return [a, b]
  }
  const part = (i: number, which: 0 | 1 | 2) =>
    days((d) => {
      if (!d[i]) return ""
      const [a, b] = seg(d[i], range.get())
      return which === 0 ? "─".repeat(a) : which === 1 ? "━".repeat(b - a) : "─".repeat(W - b)
    })
  const HOURS = ["12a", "3a", "6a", "9a", "12p", "3p", "6p", "9p"]
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      {/* the wide rows' header: a label over every column, the hour under each sky cell. The
          bar and the sky placeholders are a row's own text, unseen: box-drawing and the sky
          glyph come from other fonts than the digits, so widthChars alone sat 18px off (measured) */}
      {wide && (
        <box cssClasses={["day", "day-head"]} spacing={8}>
          <label cssClasses={["dim"]} label="day" widthChars={5} xalign={0} />
          <label cssClasses={["sky"]} label={glyph(0)} opacity={0} />
          <label cssClasses={["desc"]} label="sky" widthChars={13} xalign={0} />
          <label cssClasses={["dim"]} label="lo" widthChars={4} xalign={1} />
          <box cssClasses={["range"]}><label cssClasses={["track"]} label={"─".repeat(W)} opacity={0} /></box>
          <label cssClasses={["dim"]} label="hi" widthChars={4} xalign={0} />
          <box cssClasses={["skies"]} homogeneous>
            {HOURS.map((h) => <label cssClasses={["dim", "sm"]} label={h} />)}
          </box>
          <label cssClasses={["dim", "sm"]} label="wind        rain       uv" widthChars={30} xalign={0} />
          <label cssClasses={["dim", "sm"]} label="rise       set" widthChars={22} xalign={0} />
          <label cssClasses={["dim", "sm"]} label="chance" hexpand xalign={1} />
        </box>
      )}
      {Array.from({ length: 6 }, (_, i) => (
        <box cssClasses={["day"]} spacing={8} visible={days((d) => i < d.length)}>
          <label cssClasses={["dim"]} label={days((d) => (d[i] ? dow(d[i].t, i) : ""))} widthChars={5} xalign={0} />
          <label cssClasses={["sky"]} label={days((d) => (d[i] ? glyph(d[i].code) : ""))} />
          <label cssClasses={["desc"]} label={days((d) => (d[i] ? describe(d[i].code) : ""))} widthChars={13} xalign={0} ellipsize={3} />
          <label cssClasses={["dim"]} label={days((d) => (d[i] ? `${Math.round(d[i].low)}°` : ""))} widthChars={4} xalign={1} />
          <box cssClasses={["range"]}>
            <label cssClasses={["track"]} label={part(i, 0)} />
            <label cssClasses={["span"]} label={part(i, 1)} />
            <label cssClasses={["track"]} label={part(i, 2)} />
          </box>
          <label cssClasses={["amber"]} label={days((d) => (d[i] ? `${Math.round(d[i].high)}°` : ""))} widthChars={4} xalign={0} />
          {wide && (
            <box cssClasses={["skies"]} homogeneous>
              {/* eight equal cells: the glyphs ink at different widths, so a joined string wandered the columns after it */}
              {Array.from({ length: 8 }, (_, k) => <label cssClasses={["sky"]} label={days((d) => { const c = d[i]?.skies?.[k]; return typeof c === "number" ? glyph(c) : "" })} />)}
            </box>
          )}
          {wide && <label cssClasses={["dim", "sm"]} label={days((d) => (d[i] ? `\u{f059d} ${Math.round(d[i].windMax ?? 0)} mph   \u{f0597} ${(d[i].precip ?? 0).toFixed(2)} in   uv ${Math.round(d[i].uv)}` : ""))} widthChars={30} xalign={0} />}
          {wide && <label cssClasses={["dim", "sm"]} label={days((d) => (d[i] ? `\u{f059c} ${clock(d[i].sunrise)}   \u{f059b} ${clock(d[i].sunset)}` : ""))} widthChars={22} xalign={0} />}
          {/* icon and number apart, the number in a fixed cell: one label slid the icon by digit count */}
          <box hexpand halign={Gtk.Align.END} spacing={4}>
            <label cssClasses={days((d) => ["sm", (d[i]?.rain ?? 0) >= 30 ? "cyan" : "dim"])} label={days((d) => (d[i] && d[i].rain > 0 ? "\u{f0597}" : ""))} />
            <label cssClasses={days((d) => ["sm", (d[i]?.rain ?? 0) >= 30 ? "cyan" : "dim"])} label={days((d) => (d[i] && d[i].rain > 0 ? `${d[i].rain}%` : ""))} widthChars={4} xalign={1} />
          </box>
        </box>
      ))}
    </box>
  )
}

export function WeatherCard({ compact = false }: { compact?: boolean } = {}) {
  const stale = weather((w) => (w.note === "stale" ? "stale — network down" : ""))
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={8}>
      <Now />
      <RuleH />
      {compact ? <Chart /> : <Hours />}
      <RuleH />
      <Days wide={compact} />
      <label cssClasses={["red", "sm"]} label={stale} xalign={0} visible={stale((n) => !!n)} />
    </box>
  )
}
