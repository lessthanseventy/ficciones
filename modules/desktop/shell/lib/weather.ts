// open-meteo, no key. Location from ~/.config/astal-shell/config.json ({"lat","lon"}); the last
// good reading is cached to disk so a dead network shows stale weather rather than nothing.
import GLib from "gi://GLib?version=2.0"
import { createPoll } from "ags/time"
import { readFileAsync, writeFileAsync } from "ags/file"
import { fetch } from "ags/fetch"

export type Hour = { t: number; temp: number; code: number; rain: number }        // t = epoch ms
export type Day = {
  t: number; code: number; high: number; low: number; rain: number; sunrise: string; sunset: string; uv: number
  skies?: number[]   // weather codes at 00, 03 … 21 — the day at a glance on the board's wide rows
  windMax?: number   // mph
  precip?: number    // inches, the day's sum
}

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

// nf-weather, never emoji: a colour-emoji glyph ignores the palette entirely (it renders as a
// bright orange tile with white ink, which is both off-theme and off-contrast). These take
// whatever colour the cell asks for, like every other glyph on the bar.
const glyphs: [number, string][] = [
  [0, "\ue30d"], [1, "\ue302"], [2, "\ue302"], [3, "\ue312"], [45, "\ue313"], [48, "\ue313"],
  [51, "\ue309"], [53, "\ue309"], [55, "\ue318"], [61, "\ue318"], [63, "\ue318"], [65, "\ue318"],
  [71, "\ue31a"], [73, "\ue31a"], [75, "\ue31a"], [80, "\ue309"], [81, "\ue318"], [82, "\ue31d"],
  [95, "\ue31d"], [96, "\ue31d"], [99, "\ue31d"],
]
/** A word or two for a WMO code: the forecast rows read, not just glyph. */
export function describe(code?: number): string {
  if (code === undefined) return ""
  if (code === 0) return "clear"
  if (code === 1) return "mostly clear"
  if (code === 2) return "partly cloudy"
  if (code === 3) return "overcast"
  if (code <= 48) return "fog"
  if (code <= 55) return "drizzle"
  if (code <= 57) return "icy drizzle"
  if (code <= 65) return "rain"
  if (code <= 67) return "icy rain"
  if (code <= 77) return "snow"
  if (code <= 82) return "showers"
  if (code <= 86) return "snow showers"
  return "storms"
}
export function glyph(code?: number): string {
  if (code === undefined) return "·"
  let g = "\ue312"
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
      `&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max,wind_speed_10m_max,precipitation_sum` +
      `&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch&timezone=auto&forecast_days=6`
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
      // hourly comes as 24 rows per day in the query's order, day i at i*24
      skies: Array.from({ length: 8 }, (_, k) => j.hourly.weather_code[i * 24 + k * 3]).filter((c: unknown) => typeof c === "number"),
      windMax: j.daily.wind_speed_10m_max?.[i], precip: j.daily.precipitation_sum?.[i],
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
    console.warn("weather: fetch failed:", String(e))
    try {
      const cached: Weather = JSON.parse(await readFileAsync(cachePath))
      return { ...cached, note: "stale" }
    } catch {
      return { ok: false, note: String(e) }
    }
  }
}

// Ticks every minute but only fetches every 15 — or every minute while the last try failed,
// so one bad fetch at login does not mean 15 minutes of "stale".
const FRESH = 15 * 60_000
let last: Weather = { ok: false, note: "…" }
export const weather = createPoll<Weather>(last, 60_000, async () => {
  const due = !last.ok || last.note === "stale" || Date.now() - (last.at ?? 0) > FRESH
  if (!due) return last
  last = await fetchWeather()
  return last
})
