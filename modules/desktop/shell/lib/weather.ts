// open-meteo, no key. Location from ~/.config/astal-shell/config.json ({"lat","lon"}); the last
// good reading is cached to disk so a dead network shows stale weather rather than nothing.
import GLib from "gi://GLib?version=2.0"
import { createPoll } from "ags/time"
import { readFileAsync, writeFileAsync } from "ags/file"
import { fetch } from "ags/fetch"

export type Weather = {
  ok: boolean
  temp?: number      // °F
  code?: number      // WMO weather code
  wind?: number      // mph
  high?: number
  low?: number
  at?: number        // epoch ms of the reading
  note?: string      // why not ok
}

const cfgPath = `${GLib.get_user_config_dir()}/astal-shell/config.json`
const cachePath = `${GLib.get_user_cache_dir()}/astal-shell/weather.json`

const glyphs: [number, string][] = [
  [0, "☀"], [1, "🌤"], [2, "⛅"], [3, "☁"], [45, "🌫"], [48, "🌫"],
  [51, "🌦"], [53, "🌦"], [55, "🌧"], [61, "🌧"], [63, "🌧"], [65, "🌧"],
  [71, "🌨"], [73, "🌨"], [75, "❄"], [80, "🌦"], [81, "🌧"], [82, "⛈"],
  [95, "⛈"], [96, "⛈"], [99, "⛈"],
]
export function glyph(code?: number): string {
  if (code === undefined) return "·"
  let g = "☁"
  for (const [c, s] of glyphs) if (code >= c) g = s
  return g
}

async function readLocation(): Promise<{ lat: number; lon: number } | null> {
  try {
    const { lat, lon } = JSON.parse(await readFileAsync(cfgPath))
    return typeof lat === "number" && typeof lon === "number" ? { lat, lon } : null
  } catch {
    return null
  }
}

async function fetchWeather(): Promise<Weather> {
  const loc = await readLocation()
  if (!loc) return { ok: false, note: "set lat/lon in ~/.config/astal-shell/config.json" }
  try {
    const url =
      `https://api.open-meteo.com/v1/forecast?latitude=${loc.lat}&longitude=${loc.lon}` +
      `&current=temperature_2m,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=1`
    const res = await fetch(url)
    const j: any = await res.json()
    const w: Weather = {
      ok: true,
      temp: j.current.temperature_2m,
      code: j.current.weather_code,
      wind: j.current.wind_speed_10m,
      high: j.daily.temperature_2m_max[0],
      low: j.daily.temperature_2m_min[0],
      at: Date.now(),
    }
    writeFileAsync(cachePath, JSON.stringify(w)).catch(() => void 0)
    return w
  } catch (e) {
    try {
      const cached: Weather = JSON.parse(await readFileAsync(cachePath))
      return { ...cached, note: "stale" }
    } catch {
      return { ok: false, note: String(e) }
    }
  }
}

// 15 min; the poll's first sample fires at once.
export const weather = createPoll<Weather>({ ok: false, note: "…" }, 15 * 60_000, fetchWeather)
