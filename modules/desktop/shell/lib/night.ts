// Night light: hyprsunset follows sunset/sunrise from the weather fetch. A manual toggle
// overrides until the next natural transition, then the schedule takes over again. The
// temperature and whether it follows the sun at all are settings (look.night*).
import { createState } from "ags"
import { interval } from "ags/time"
import { execAsync } from "ags/process"
import { weather } from "./weather"
import { setting } from "./settings"

export const [night, setNightState] = createState(false)
let manual: boolean | null = null   // a user choice, cleared at the next transition
let applied: boolean | null = null

function apply(on: boolean) {
  if (applied === on) return
  applied = on
  setNightState(on)
  execAsync(["hyprctl", "hyprsunset", ...(on ? ["temperature", String(setting("look.nightKelvin").peek())] : ["identity"])]).catch(console.error)
}

/** Is it after sunset or before sunrise, per today's forecast? null when unknown. */
function isDark(): boolean | null {
  const d = weather.peek().days?.[0]
  if (!d) return null
  const now = Date.now()
  return now < Date.parse(d.sunrise) || now >= Date.parse(d.sunset)
}

let lastDark: boolean | null = null
function tick() {
  if (!setting("look.nightFollowsSun").peek()) return
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
setting("look.nightFollowsSun").subscribe(() => { manual = null; tick() })
// a new temperature shows at once while it is on
setting("look.nightKelvin").subscribe(() => { if (applied) { applied = null; apply(true) } })
