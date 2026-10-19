// The shell's settings: one JSON file every surface reads, written by the Settings surface and
// `astal-shell set`; a hand edit applies live. A setting is a choice; where things are (pinned
// windows, frecency, dismissed alerts) is state, and stays under ~/.local/state/astal-shell.
import GLib from "gi://GLib?version=2.0"
import Gio from "gi://Gio?version=2.0"
import { createState, type Accessor, type Setter } from "ags"
import { timeout, type Timer } from "ags/time"
import { load, dump, parseCli, type Value, type Values } from "./settings-core"

const DEFAULTS = {
  /** what the backdrop shows at login: "photo", "random", or an ambient's name */
  "backdrop.startup": "random",
  "backdrop.rotateSeconds": 90,
  /** ambients left out of the random rotation (a named one can still be held) */
  "backdrop.ambientsOff": [] as string[],
  /** every other rotation turn is an xscreensaver hack */
  "backdrop.hacks": true,
  "backdrop.hacksOff": [] as string[],
  /** hacks draw at this fraction of the monitor, stretched to fit: smaller is smoother and softer */
  "backdrop.hackScale": 0.5,
  /** how often the smooth ambients step; a multiple of 5 (the slow ones' rate) */
  "backdrop.smoothHz": 15,
  /** the photo backdrop picks a new image this often */
  "wallpaper.rotateMinutes": 5,
  "look.glass": true,
  /** both active and inactive windows: the background is not dimmer than the foreground */
  "look.glassOpacity": 0.9,
  /** "off", "subtle" or "full": a screen shader over the whole output */
  "look.crt": "off",
  "look.nightKelvin": 4000,
  /** night light on at sunset and off at sunrise; off, only the toggle moves it */
  "look.nightFollowsSun": true,
  /** how long a toast stays up, unless the sender says; critical ones stay until clicked */
  /** hold off hypridle's lock, screen-off and suspend */
  "power.awake": true,
  "notify.toastSeconds": 6,
  "notify.maxToasts": 5,
  "notify.dnd": false,
  /** the rail's audio bars; the visualiser's whole CPU cost while sound plays */
  "sound.vizFps": 30,
  /** bars per channel in the rail's visualiser */
  "sound.vizBars": 24,
  /** how long the pointer rests on a bar item before its card opens */
  "feel.hoverDwellMs": 500,
  /** how long a card stays after the pointer leaves it */
  "feel.hoverGraceMs": 350,
  "feel.osdHoldMs": 1400,
  /** the pointer parked on a monitor's right edge this long opens the hub */
  "feel.hotEdgeMs": 400,
}
type Defaults = typeof DEFAULTS
export type SettingKey = keyof Defaults
type KeyOf<T> = { [K in SettingKey]: Defaults[K] extends T ? K : never }[SettingKey]
export type NumberKey = KeyOf<number>
export type BoolKey = KeyOf<boolean>
export const PATH = `${GLib.get_user_config_dir()}/ficciones/shell.json`

function read(): string | null {
  try {
    const [ok, bytes] = GLib.file_get_contents(PATH)
    return ok ? new TextDecoder().decode(bytes) : null
  } catch { return null } // no file yet: the defaults
}

const first = load(DEFAULTS, read())
if (first.error) console.error(`settings: ${PATH}: ${first.error}; using the defaults`)
let extra = first.extra
const states = Object.fromEntries(Object.entries(first.values).map(([k, v]) => [k, createState<Value>(v)])) as {
  [K in SettingKey]: [Accessor<Defaults[K]>, Setter<Defaults[K]>]
}
const keys = Object.keys(DEFAULTS) as SettingKey[]
const values = () => Object.fromEntries(keys.map((k) => [k, states[k][0].peek()])) as Values
const same = (a: Value, b: Value) => JSON.stringify(a) === JSON.stringify(b)

let written: string | null = null
let pending: Timer | null = null
function save() {
  pending?.cancel()
  pending = timeout(300, () => {
    pending = null
    written = dump(values(), extra)
    try {
      GLib.mkdir_with_parents(GLib.path_get_dirname(PATH), 0o755)
      GLib.file_set_contents(PATH, written)
    } catch (e) { console.error(`settings: write ${PATH}: ${e}`) }
  })
}

/** A setting, live: it follows the menu, the CLI and hand edits of the file. */
export const setting = <K extends SettingKey>(k: K): Accessor<Defaults[K]> => states[k][0]
export function setSetting<K extends SettingKey>(k: K, v: Defaults[K]) {
  if (same(states[k][0].peek(), v)) return
  states[k][1](v)
  save()
}

// a hand edit (or a deleted file) applies live; our own write comes back as the same text and is skipped
const monitor = Gio.File.new_for_path(PATH).monitor_file(Gio.FileMonitorFlags.NONE, null)
// pinned: no closure holds it once the module has run, and a collected monitor goes silent
;(globalThis as { settingsMonitor?: Gio.FileMonitor }).settingsMonitor = monitor
monitor.connect("changed", () => {
  const text = read()
  if (text === written) return
  const r = load(DEFAULTS, text)
  // a half-saved edit keeps what is running rather than snapping everything back to the defaults
  if (r.error) return console.error(`settings: ${PATH}: ${r.error}; keeping the current settings`)
  extra = r.extra
  for (const k of keys) if (!same(states[k][0].peek(), r.values[k])) (states[k][1] as Setter<Value>)(r.values[k])
})

/** `astal-shell get [KEY]`: one value as JSON, or every setting. */
export function getCli(k?: string): string {
  if (!k) return dump(values(), {}).trimEnd()
  return k in states ? JSON.stringify(states[k as SettingKey][0].peek()) : `no setting ${k}: ${keys.join(" ")}`
}
/** `astal-shell set KEY TEXT`: TEXT as the setting's type (a list is comma-separated). */
export function setCli(k: string | undefined, text: string): string {
  if (!k || !(k in states)) return `usage: set KEY VALUE; keys: ${keys.join(" ")}`
  const v = parseCli(DEFAULTS[k as SettingKey], text)
  if (v instanceof Error) return `${k}: ${v.message}`
  setSetting(k as SettingKey, v as never)
  return "ok"
}
