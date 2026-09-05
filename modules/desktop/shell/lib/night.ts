// Night light: hyprsunset follows sunset/sunrise from the weather fetch. A manual toggle
// overrides until the next natural transition, then the schedule takes over again.
import { createState } from "ags"
import { interval } from "ags/time"
import { execAsync } from "ags/process"
import { weather } from "./weather"

export const NIGHT_K = 4000
export const [night, setNightState] = createState(false)
let manual: boolean | null = null   // a user choice, cleared at the next transition
let applied: boolean | null = null

function apply(on: boolean) {
  if (applied === on) return
  applied = on
  setNightState(on)
  execAsync(["hyprctl", "hyprsunset", ...(on ? ["temperature", String(NIGHT_K)] : ["identity"])]).catch(console.error)
}

/** Is it after sunset or before sunrise, per today's forecast? null when unknown. */
function isDark(): boolean | null {
  const d = weather.get().days?.[0]
  if (!d) return null
  const now = Date.now()
  return now < Date.parse(d.sunrise) || now >= Date.parse(d.sunset)
}

let lastDark: boolean | null = null
function tick() {
  const dark = isDark()
  if (dark === null) return
  if (lastDark !== null && dark !== lastDark) manual = null   // a transition clears the override
  lastDark = dark
  apply(manual ?? dark)
}

export function toggleNight() {
  manual = !(applied ?? false)
  apply(manual)
}

interval(60_000, tick)
weather.subscribe(tick)
