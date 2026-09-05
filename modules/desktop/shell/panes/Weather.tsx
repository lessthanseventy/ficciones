// WEATHER: now, today, wind. open-meteo via lib/weather.ts.
import Gtk from "gi://Gtk?version=4.0"
import { weather, glyph } from "../lib/weather"

export function WeatherCard() {
  const big = weather((w) => (w.ok ? `${Math.round(w.temp!)}°` : "—"))
  const g = weather((w) => (w.ok ? glyph(w.code) : "\u{f0590}"))
  const line = weather((w) => (w.ok ? `${Math.round(w.low!)}° – ${Math.round(w.high!)}° today` : w.note ?? ""))
  const wind = weather((w) => (w.ok ? `wind ${Math.round(w.wind!)} mph` : ""))
  const note = weather((w) => w.note === "stale" ? "stale — network down" : "")
  return (
    <box spacing={16}>
      <label cssClasses={["wx-glyph"]} label={g} valign={Gtk.Align.START} />
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2} hexpand>
        <label cssClasses={["huge"]} label={big} xalign={0} />
        <label label={line} xalign={0} />
        <label cssClasses={["dim"]} label={wind} xalign={0} />
        <label cssClasses={["red", "sm"]} label={note} xalign={0} visible={note((n) => !!n)} />
      </box>
    </box>
  )
}
