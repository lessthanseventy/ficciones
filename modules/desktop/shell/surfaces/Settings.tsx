// Settings: every preference the shell has, over lib/settings.ts (~/.config/ficciones/shell.json).
// Super+Comma, Super+Shift+click on the Aleph in the corner, or `astal-shell toggle settings [SECTION]`;
// Esc closes. Each control writes its setting and the shell follows at once.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { createState, createComputed, createRoot, type Accessor } from "ags"
import { Panel } from "../lib/tui"
import { setting, setSetting, PATH } from "../lib/settings"
import { hackNames } from "../lib/xscreensaver"
import { MODE_NAMES } from "./Backdrop"
import { theme, setTheme, THEMES } from "../lib/theme"
import { crt, setCrt, MODES as CRT_MODES } from "../lib/crt"

let win: Astal.Window | null = null
let hackGrid: Gtk.FlowBox | null = null
let search: Gtk.Entry | null = null
const [query, setQuery] = createState("")
const [hacks, setHacks] = createState<string[]>([])
const SECTIONS = ["backdrop", "look"] as const
const [section, setSection] = createState<(typeof SECTIONS)[number]>("backdrop")

/** Open (on `sec` when named) or close the surface. */
export function toggleSettings(sec?: string) {
  if (!win) return
  if ((SECTIONS as readonly string[]).includes(sec ?? "")) setSection(sec as (typeof SECTIONS)[number])
  if (win.visible && !sec) return void (win.visible = false)
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (mon) win.gdkmonitor = mon
  fillHacks()
  win.visible = true
  search?.grab_focus()
}

/** An outlined toggle, amber when on — the dashboard's shape, a word wide. */
function Chip({ label, on, onClicked }: { label: string | Accessor<string>; on: Accessor<boolean>; onClicked: () => void }) {
  return (
    <button cssClasses={on((o) => ["toggle", "set-chip", ...(o ? ["chip"] : [])])} onClicked={onClicked}>
      <label cssClasses={["sm"]} label={label} />
    </button>
  )
}

/** A setting's row: what it is on the left, its control on the right. */
function Row({ label, hint, children }: { label: string; hint?: string; children: JSX.Element | JSX.Element[] }) {
  return (
    <box cssClasses={["set-row"]} spacing={16}>
      <box orientation={Gtk.Orientation.VERTICAL} cssClasses={["set-label"]} valign={Gtk.Align.START}>
        <label cssClasses={["k"]} label={label} xalign={0} />
        {hint ? <label cssClasses={["dim", "sm"]} label={hint} xalign={0} wrap maxWidthChars={22} /> : <box />}
      </box>
      <box hexpand>{children}</box>
    </box>
  )
}

const flow = (children: JSX.Element[], perLine = 7) => (
  <Gtk.FlowBox selectionMode={Gtk.SelectionMode.NONE} maxChildrenPerLine={perLine} minChildrenPerLine={1} columnSpacing={4} rowSpacing={4} homogeneous hexpand>
    {children}
  </Gtk.FlowBox>
)

const toggleIn = (key: "backdrop.ambientsOff" | "backdrop.hacksOff", name: string) => {
  const off = setting(key).peek()
  setSetting(key, off.includes(name) ? off.filter((x) => x !== name) : [...off, name])
}

/** − value +, stepping a number setting through `stops` (a value between two stops goes to the next) */
function Stepper({ k, stops, fmt }: { k: "backdrop.rotateSeconds" | "look.glassOpacity" | "look.nightKelvin"; stops: number[]; fmt: (n: number) => string }) {
  const step = (dir: 1 | -1) => {
    const now = setting(k).peek()
    const next = dir > 0 ? stops.find((t) => t > now + 1e-9) : [...stops].reverse().find((t) => t < now - 1e-9)
    if (next !== undefined) setSetting(k, next)
  }
  return (
    <box spacing={8} valign={Gtk.Align.START}>
      <button cssClasses={["toggle", "set-step"]} onClicked={() => step(-1)}><label label="−" /></button>
      <label cssClasses={["set-value"]} label={setting(k)(fmt)} widthChars={9} />
      <button cssClasses={["toggle", "set-step"]} onClicked={() => step(1)}><label label="+" /></button>
    </box>
  )
}
const range = (from: number, to: number, by: number) => Array.from({ length: Math.round((to - from) / by) + 1 }, (_, i) => +(from + i * by).toFixed(4))
const OnOff = ({ k }: { k: "backdrop.hacks" | "look.glass" | "look.nightFollowsSun" }) => (
  <box valign={Gtk.Align.START}>
    <Chip label={setting(k)((v) => (v ? "on" : "off"))} on={setting(k)} onClicked={() => setSetting(k, !setting(k).peek())} />
  </box>
)
const fmtTurn = (s: number) => (s < 60 ? `${s} s` : s % 60 ? `${Math.floor(s / 60)} m ${s % 60} s` : `${s / 60} min`)

/** The hack chips, built once the list has loaded (it comes after startup, from xss-host); in a
 * root of their own, as they are made outside the surface's render. */
function fillHacks() {
  if (!hackGrid || hackGrid.get_first_child() || !hackNames().length) return
  const grid = hackGrid, off = setting("backdrop.hacksOff")
  setHacks(hackNames())
  createRoot(() => {
    for (const name of hackNames())
      grid.append(<Chip label={name} on={off((o) => !o.includes(name))} onClicked={() => toggleIn("backdrop.hacksOff", name)} /> as Gtk.Widget)
  })
  hackGrid.set_filter_func((child) => {
    const q = query.peek().trim().toLowerCase()
    return !q || ((child.get_child() as Gtk.Button)?.get_child() as Gtk.Label)?.get_label().includes(q)
  })
}

function Backdrop() {
  const startup = setting("backdrop.startup")
  const ambientsOff = setting("backdrop.ambientsOff")
  const hacksOff = setting("backdrop.hacksOff")
  const startChips = ["photo", "random", ...MODE_NAMES].map((m) => (
    <Chip label={m} on={startup((s) => s === m)} onClicked={() => setSetting("backdrop.startup", m)} />
  ))
  const ambientChips = MODE_NAMES.map((m) => (
    <Chip label={m} on={ambientsOff((o) => !o.includes(m))} onClicked={() => toggleIn("backdrop.ambientsOff", m)} />
  ))
  return (
    <Panel title="BACKDROP" cssClasses={["set-section"]} spacing={10} visible={section((s) => s === "backdrop")}>
      <Row label="at login" hint="photo, the rotation, or one ambient held">{flow(startChips)}</Row>
      <Row label="turn length" hint="each ambient or hack, then the next">
        <Stepper k="backdrop.rotateSeconds" stops={[10, 30, 60, 90, 120, 300, 600, 1800]} fmt={fmtTurn} />
      </Row>
      <Row label="ambients" hint="in the rotation; off ones can still be held">{flow(ambientChips)}</Row>
      <Row label="hack turns" hint="every other turn, an xscreensaver hack">
        <OnOff k="backdrop.hacks" />
      </Row>
      <Row label="hacks" hint="which ones the hack turns draw from">
        <box orientation={Gtk.Orientation.VERTICAL} spacing={6} hexpand>
          <box spacing={8} cssClasses={["prompt", "set-search"]}>
            <label cssClasses={["ps"]} label="/" />
            <entry
              hexpand
              placeholderText="filter"
              $={(self) => { search = self; self.connect("changed", () => { setQuery(self.text); hackGrid?.invalidate_filter() }) }}
            />
            <label cssClasses={["dim", "sm"]} label={createComputed(() => `${hacks().filter((x) => !hacksOff().includes(x)).length} of ${hacks().length} on`)} />
            <button cssClasses={["toggle", "set-step"]} onClicked={() => setSetting("backdrop.hacksOff", [])}><label cssClasses={["sm"]} label="all" /></button>
            <button cssClasses={["toggle", "set-step"]} onClicked={() => setSetting("backdrop.hacksOff", [...hackNames()])}><label cssClasses={["sm"]} label="none" /></button>
          </box>
          <Gtk.ScrolledWindow cssClasses={["set-hacks"]} hscrollbarPolicy={Gtk.PolicyType.NEVER} minContentHeight={300} maxContentHeight={300}>
            <Gtk.FlowBox
              selectionMode={Gtk.SelectionMode.NONE}
              maxChildrenPerLine={6}
              minChildrenPerLine={1}
              columnSpacing={4}
              rowSpacing={4}
              homogeneous
              valign={Gtk.Align.START}
              $={(self) => { hackGrid = self }}
            />
          </Gtk.ScrolledWindow>
        </box>
      </Row>
    </Panel>
  )
}

function Look() {
  return (
    <Panel title="LOOK" cssClasses={["set-section"]} spacing={10} visible={section((s) => s === "look")}>
      <Row label="theme" hint="uqbar dark, zahir light; every app follows">
        {flow(THEMES.map((t) => <Chip label={t} on={theme((c) => c === t)} onClicked={() => setTheme(t)} />))}
      </Row>
      <Row label="glass" hint="see-through windows; a playing video makes them opaque"><OnOff k="look.glass" /></Row>
      <Row label="glass opacity" hint="how solid a glass window is">
        <Stepper k="look.glassOpacity" stops={range(0.5, 1, 0.05)} fmt={(n) => `${Math.round(n * 100)} %`} />
      </Row>
      <Row label="crt" hint="scanlines over the whole screen; costs GPU">
        {flow(CRT_MODES.map((m) => <Chip label={m} on={crt((c) => c === m)} onClicked={() => setCrt(m)} />))}
      </Row>
      <Row label="night light" hint="warmer screen at sunset, back at sunrise"><OnOff k="look.nightFollowsSun" /></Row>
      <Row label="night warmth" hint="lower is warmer">
        <Stepper k="look.nightKelvin" stops={range(2500, 6500, 250)} fmt={(n) => `${n} K`} />
      </Row>
    </Panel>
  )
}

export default function Settings() {
  return (
    <window
      $={(self) => {
        win = self
        // capture: Esc closes before the focused filter can take it
        const k = new Gtk.EventControllerKey({ propagationPhase: Gtk.PropagationPhase.CAPTURE })
        k.connect("key-pressed", (_c, key) => (key === Gdk.KEY_Escape ? ((self.visible = false), true) : false))
        self.add_controller(k)
      }}
      visible={false}
      cssClasses={["settings"]}
      namespace="astal-shell-settings"
      name="settings"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.EXCLUSIVE}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP}
      marginTop={60}
      application={app}
    >
      <Panel title={`SETTINGS · ${PATH.replace(/^\/home\/[^/]+/, "~")}`} cssClasses={["settings-pane", "focused"]}>
        <box spacing={16}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={4} cssClasses={["set-nav"]} valign={Gtk.Align.START}>
            {SECTIONS.map((s) => <Chip label={s} on={section((c) => c === s)} onClicked={() => setSection(s)} />)}
          </box>
          <box orientation={Gtk.Orientation.VERTICAL} hexpand>
            <Backdrop />
            <Look />
          </box>
        </box>
      </Panel>
    </window>
  )
}
