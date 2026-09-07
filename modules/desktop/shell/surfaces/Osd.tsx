// The OSD: volume and brightness, bottom centre of the focused monitor, up for 1.4 s after a
// change. Prominent on purpose (Andrew, 2026-09-05: headphone buttons change the volume with
// nothing on screen). A change made from a popover slider is already visible, so those call
// `quietOsd()` first and the OSD stays down.
import { volumeGlyph } from "../lib/icons"
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Wp from "gi://AstalWp"
import Brightness from "gi://AstalBrightness"
import { createState } from "ags"
import { timeout, type Timer } from "ags/time"
import { Panel } from "../lib/tui"
import { meter, pct } from "../lib/format"
import { onGammaChange } from "../lib/brightness"

const HOLD_MS = 1400
type Kind = "volume" | "brightness" | "text"
const [osd, setOsd] = createState<{ kind: Kind; frac: number; muted: boolean; icon: string; title?: string; text?: string } | null>(null)

let hide: Timer | null = null
let quietUntil = 0
/** The next second of changes came from a slider the user is looking at: no OSD. */
export const quietOsd = () => { quietUntil = Date.now() + 1000 }

function show(kind: Kind, frac: number, muted = false) {
  if (Date.now() < quietUntil) return
  const icon = kind === "brightness" ? "\u{f00e0}" : volumeGlyph(frac, muted)
  setOsd({ kind, frac, muted, icon })
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (win && mon) win.gdkmonitor = mon
  hide?.cancel()
  hide = timeout(HOLD_MS, () => setOsd(null))
}

let win: Astal.Window | null = null

/** A word on screen for a moment: the backdrop mode, a theme change. */
export function showText(title: string, text: string, icon = "\u{f0e2a}") {
  setOsd({ kind: "text", frac: 0, muted: false, icon, title, text })
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (win && mon) win.gdkmonitor = mon
  hide?.cancel()
  hide = timeout(HOLD_MS, () => setOsd(null))
}

/** Watch the sources. The first notify of each is the initial value, not a change. */
function watch() {
  const speaker = Wp.get_default()?.defaultSpeaker
  if (speaker) {
    let armed = false
    const onVol = () => { if (armed) show("volume", speaker.volume, speaker.mute) }
    speaker.connect("notify::volume", onVol)
    speaker.connect("notify::mute", onVol)
    timeout(2000, () => { armed = true })
  }
  onGammaChange((v) => show("brightness", v))
  const screen = Brightness.get_default()?.screen
  if (screen) {
    let armed = false
    screen.connect("notify::brightness", () => { if (armed) show("brightness", screen.brightness) })
    timeout(2000, () => { armed = true })
  }
}

export default function Osd() {
  watch()
  return (
    <window
      $={(self) => (win = self)}
      visible={osd((o) => !!o)}
      cssClasses={["osd"]}
      namespace="astal-shell-osd"
      name="osd"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.NONE}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.BOTTOM}
      marginBottom={96}
      application={app}
    >
      <Panel title={osd((o) => (o?.kind === "text" ? o.title ?? "" : o?.kind === "brightness" ? "\u{f00e0}  BRIGHTNESS" : "\u{f057e}  VOLUME"))} cssClasses={osd((o) => ["osd-pane", ...(o?.muted ? ["muted"] : [])])}>
        <box spacing={16}>
          <label cssClasses={["osd-icon"]} label={osd((o) => o?.icon ?? "")} />
          <label cssClasses={["osd-bar"]} label={osd((o) => meter(o?.frac ?? 0, 30))} visible={osd((o) => o?.kind !== "text")} />
          <label cssClasses={["osd-num"]} label={osd((o) => (o?.muted ? "mute" : pct(o?.frac ?? 0)))} widthChars={4} xalign={1} visible={osd((o) => o?.kind !== "text")} />
          <label cssClasses={["osd-num"]} label={osd((o) => o?.text ?? "")} xalign={0} visible={osd((o) => o?.kind === "text")} />
        </box>
      </Panel>
    </window>
  )
}
