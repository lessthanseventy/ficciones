// open-meteo, no key. Location from ~/.config/astal-shell/config.json ({"lat","lon"}); the last
// good reading is cached to disk so a dead network shows stale weather rather than nothing.
import GLib from "gi://GLib?version=2.0"
import { createPoll } from "ags/time"
import { readFileAsync, writeFileAsync } from "ags/file"
import { fetch } from "ags/fetch"

export type Hour = { t: number; temp: number; code: number; rain: number }        // t = epoch ms
export type Day = { t: number; code: number; high: number; low: number; rain: number; sunrise: string; sunset: string; uv: number }

export type Weather = {
  ok: boolean
  temp?: number      // °F
  feels?: number
  humidity?: number  // %
  code?: number      // WMO weather code
  wind?: number      // mph
  high?: number
  low?: number
  hours?: Hour[]     // the next 24, hourly
  days?: Day[]       // today + 5
  at?: number        // epoch ms of the reading
  note?: string      // why not ok
}

const cfgPath = `${GLib.get_user_config_dir()}/astal-shell/config.json`
const cachePath = `${GLib.get_user_cache_dir()}/astal-shell/weather.json`

const glyphs: [number, string][] = [
  [0, "☀\uFE0F"], [1, "🌤"], [2, "⛅"], [3, "☁\uFE0F"], [45, "🌫"], [48, "🌫"],
  [51, "🌦"], [53, "🌦"], [55, "🌧"], [61, "🌧"], [63, "🌧"], [65, "🌧"],
  [71, "🌨"], [73, "🌨"], [75, "❄\uFE0F"], [80, "🌦"], [81, "🌧"], [82, "⛈"],
  [95, "⛈"], [96, "⛈"], [99, "⛈"],
]
export function glyph(code?: number): string {
  if (code === undefined) return "·"
  let g = "☁\uFE0F"
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
      `&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m` +
      `&hourly=temperature_2m,weather_code,precipitation_probability` +
      `&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max` +
      `&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=6`
    const res = await fetch(url)
    const j: any = await res.json()
    const now = Date.now()
    const hours: Hour[] = j.hourly.time
      .map((t: string, i: number) => ({ t: Date.parse(t), temp: j.hourly.temperature_2m[i], code: j.hourly.weather_code[i], rain: j.hourly.precipitation_probability[i] ?? 0 }))
      .filter((h: Hour) => h.t >= now - 3600_000)
      .slice(0, 24)
    const days: Day[] = j.daily.time.map((t: string, i: number) => ({
      t: Date.parse(t), code: j.daily.weather_code[i], high: j.daily.temperature_2m_max[i], low: j.daily.temperature_2m_min[i],
      rain: j.daily.precipitation_probability_max[i] ?? 0, sunrise: j.daily.sunrise[i], sunset: j.daily.sunset[i], uv: j.daily.uv_index_max[i] ?? 0,
    }))
    const w: Weather = {
      ok: true,
      temp: j.current.temperature_2m,
      feels: j.current.apparent_temperature,
      humidity: j.current.relative_humidity_2m,
      code: j.current.weather_code,
      wind: j.current.wind_speed_10m,
      high: days[0]?.high,
      low: days[0]?.low,
      hours,
      days,
      at: now,
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
