// WEATHER: open-meteo now + today. No library exists for this; lib/weather.ts fetches it.
import Gtk from "gi://Gtk?version=4.0"
import { Panel } from "../lib/tui"
import { weather, glyph } from "../lib/weather"

export default function Weather() {
  const big = weather((w) => (w.ok ? `${glyph(w.code)}  ${Math.round(w.temp!)}°F` : "—"))
  const line = weather((w) => (w.ok ? `today ${Math.round(w.low!)}° – ${Math.round(w.high!)}°   wind ${Math.round(w.wind!)} mph` : ""))
  const note = weather((w) => w.note ?? (w.at ? `read ${new Date(w.at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}` : ""))
  return (
    <Panel title="WEATHER" spacing={4}>
      <label cssClasses={["huge"]} label={big} xalign={0} />
      <label label={line} xalign={0} />
      <label cssClasses={["dim"]} label={note} xalign={0} />
      <label cssClasses={["dim", "sm"]} label='location: ~/.config/astal-shell/config.json  {"lat": .., "lon": ..}' xalign={0} />
    </Panel>
  )
}
