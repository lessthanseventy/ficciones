// Settings: every preference the shell has, over lib/settings.ts (~/.config/ficciones/shell.json).
// Super+Comma, Super+Shift+click on the Aleph in the corner, or `astal-shell toggle settings [SECTION]`;
// Esc closes. Each control writes its setting and the shell follows at once.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { createState, createComputed, createRoot, type Accessor } from "ags"
import { Panel } from "../lib/tui"
import { duration } from "../lib/format"
import { closeKeys } from "../lib/keys"
import { clickawayField } from "./Clickaway"
import { setting, setSetting, PATH, type NumberKey, type BoolKey } from "../lib/settings"
import { hackNames, startPreview, stopPreview } from "../lib/xscreensaver"
import { MODE_NAMES } from "./Backdrop"
import { theme, setTheme, THEMES } from "../lib/theme"
import { crt, setCrt, MODES as CRT_MODES } from "../lib/crt"

let win: Astal.Window | null = null
let hackList: Gtk.Box | null = null
let shot: Gtk.Picture | null = null
let search: Gtk.Entry | null = null
const [hacks, setHacks] = createState<string[]>([])
const [picked, setPicked] = createState<string | null>(null)
const SECTIONS = ["backdrop", "look", "notifications", "feel"] as const
const [section, setSection] = createState<(typeof SECTIONS)[number]>("backdrop")
const PREVIEW_W = 440, PREVIEW_H = 330

/** The picked hack runs in the preview while it can be seen, and nothing runs while it cannot. */
function syncPreview() {
  const name = picked.peek()
  if (!win?.visible || section.peek() !== "backdrop" || !name) return stopPreview()
  startPreview(name, PREVIEW_W, PREVIEW_H, (t) => shot?.set_paintable(t))
}
section.subscribe(syncPreview)
const pick = (name: string) => {
  if (picked.peek() === name) return
  shot?.set_paintable(null)
  setPicked(name)
  syncPreview()
}

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
function Stepper({ k, stops, fmt }: { k: NumberKey; stops: number[]; fmt: (n: number) => string }) {
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
const OnOff = ({ k }: { k: BoolKey }) => (
  <box valign={Gtk.Align.START}>
    <Chip label={setting(k)((v) => (v ? "on" : "off"))} on={setting(k)} onClicked={() => setSetting(k, !setting(k).peek())} />
  </box>
)

/** The hack rows, built once the list has loaded (it comes after startup, from xss-host); in a
 * root of their own, as they are made outside the surface's render. A row is its mark (in the
 * rotation or not) and its name, which picks it for the preview. */
function fillHacks() {
  if (!hackList || hackList.get_first_child() || !hackNames().length) return
  const list = hackList, off = setting("backdrop.hacksOff")
  setHacks(hackNames())
  createRoot(() => {
    for (const name of hackNames())
      list.append(
        <box spacing={4} name={name}>
          <button
            cssClasses={off((o) => ["toggle", "set-mark", ...(o.includes(name) ? [] : ["chip"])])}
            tooltipText="in the rotation"
            onClicked={() => toggleIn("backdrop.hacksOff", name)}
          >
            <label cssClasses={["sm"]} label={off((o) => (o.includes(name) ? " " : "✓"))} />
          </button>
          <button hexpand cssClasses={picked((p) => ["toggle", "set-hack", ...(p === name ? ["tab"] : [])])} onClicked={() => pick(name)}>
            <label cssClasses={["sm"]} label={name} xalign={0} />
          </button>
        </box> as Gtk.Widget,
      )
  })
}

function filterHacks(q: string) {
  q = q.trim().toLowerCase()
  for (let row = hackList?.get_first_child(); row; row = row.get_next_sibling()) row.visible = !q || row.name.includes(q)
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
        <Stepper k="backdrop.rotateSeconds" stops={[10, 30, 60, 90, 120, 300, 600, 1800]} fmt={(n) => duration(n, "words")} />
      </Row>
      <Row label="photo changes" hint="a new wallpaper this often">
        <Stepper k="wallpaper.rotateMinutes" stops={[1, 2, 5, 10, 15, 30, 60, 120, 240]} fmt={(n) => (n < 60 ? `${n} min` : `${n / 60} h`)} />
      </Row>
      <Row label="ambients" hint="in the rotation; off ones can still be held">{flow(ambientChips)}</Row>
      <Row label="hack turns" hint="every other turn, an xscreensaver hack">
        <OnOff k="backdrop.hacks" />
      </Row>
      <Row label="hack sharpness" hint="drawn at this size, stretched; smaller is smoother, softer">
        <Stepper k="backdrop.hackScale" stops={[0.25, 0.33, 0.5, 0.67, 0.75, 1]} fmt={(n) => `${Math.round(n * 100)} %`} />
      </Row>
      <Row label="ambient smoothness" hint="how often the smooth ambients step; costs CPU">
        <Stepper k="backdrop.smoothHz" stops={[10, 15, 20, 25, 30]} fmt={(n) => `${n} Hz`} />
      </Row>
      <Row label="hacks" hint="pick one to watch it; ✓ puts it in the hack turns">
        <box orientation={Gtk.Orientation.VERTICAL} spacing={6} hexpand>
          <box spacing={8} cssClasses={["prompt", "set-search"]}>
            <label cssClasses={["ps"]} label="/" />
            <entry
              hexpand
              placeholderText="filter"
              $={(self) => { search = self; self.connect("changed", () => filterHacks(self.text)) }}
            />
            <label cssClasses={["dim", "sm"]} label={createComputed(() => `${hacks().filter((x) => !hacksOff().includes(x)).length} of ${hacks().length} on`)} />
            <button cssClasses={["toggle", "set-step"]} onClicked={() => setSetting("backdrop.hacksOff", [])}><label cssClasses={["sm"]} label="all" /></button>
            <button cssClasses={["toggle", "set-step"]} onClicked={() => setSetting("backdrop.hacksOff", [...hackNames()])}><label cssClasses={["sm"]} label="none" /></button>
          </box>
          <box spacing={12} cssClasses={["set-hacks"]}>
            <Gtk.ScrolledWindow hexpand hscrollbarPolicy={Gtk.PolicyType.NEVER} minContentHeight={PREVIEW_H + 40} maxContentHeight={PREVIEW_H + 40}>
              <box orientation={Gtk.Orientation.VERTICAL} spacing={2} valign={Gtk.Align.START} $={(self) => { hackList = self }} />
            </Gtk.ScrolledWindow>
            <box orientation={Gtk.Orientation.VERTICAL} spacing={6} valign={Gtk.Align.START}>
              <overlay cssClasses={["set-preview"]}>
                <Gtk.Picture widthRequest={PREVIEW_W} heightRequest={PREVIEW_H} canShrink contentFit={Gtk.ContentFit.FILL} $={(self) => { shot = self }} />
                <label $type="overlay" cssClasses={["dim", "sm"]} label="pick a hack to watch it" visible={picked((p) => !p)} />
              </overlay>
              <box spacing={8} visible={picked((p) => !!p)}>
                <label cssClasses={["k"]} hexpand xalign={0} label={picked((p) => p ?? "")} />
                <Chip
                  label={createComputed(() => (hacksOff().includes(picked() ?? "") ? "not in the rotation" : "in the rotation"))}
                  on={createComputed(() => !hacksOff().includes(picked() ?? ""))}
                  onClicked={() => { const p = picked.peek(); if (p) toggleIn("backdrop.hacksOff", p) }}
                />
              </box>
            </box>
          </box>
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

const ms = (n: number) => (n >= 1000 ? `${+(n / 1000).toFixed(2)} s` : `${n} ms`)

function Notifications() {
  return (
    <Panel title="NOTIFICATIONS" cssClasses={["set-section"]} spacing={10} visible={section((s) => s === "notifications")}>
      <Row label="do not disturb" hint="no toasts; notices still land in the hub"><OnOff k="notify.dnd" /></Row>
      <Row label="toast time" hint="unless the sender sets one; critical stays until clicked">
        <Stepper k="notify.toastSeconds" stops={[2, 3, 4, 5, 6, 8, 10, 15, 20, 30, 60]} fmt={(n) => `${n} s`} />
      </Row>
      <Row label="toasts at once" hint="more wait in the hub">
        <Stepper k="notify.maxToasts" stops={range(1, 10, 1)} fmt={(n) => `${n}`} />
      </Row>
    </Panel>
  )
}

function Feel() {
  return (
    <Panel title="FEEL" cssClasses={["set-section"]} spacing={10} visible={section((s) => s === "feel")}>
      <Row label="stay awake" hint="no idle lock, screen-off or suspend"><OnOff k="power.awake" /></Row>
      <Row label="hover to open" hint="resting on a bar item before its card opens">
        <Stepper k="feel.hoverDwellMs" stops={range(0, 1500, 100)} fmt={ms} />
      </Row>
      <Row label="Super+hover" hint="resting on a rail workspace with Super held before its windows show">
        <Stepper k="feel.superHoverMs" stops={range(0, 1500, 50)} fmt={ms} />
      </Row>
      <Row label="card grace" hint="a card stays this long after the pointer leaves">
        <Stepper k="feel.hoverGraceMs" stops={range(0, 1500, 50)} fmt={ms} />
      </Row>
      <Row label="hot edge" hint="parked on the right edge this long opens the hub">
        <Stepper k="feel.hotEdgeMs" stops={range(100, 2000, 100)} fmt={ms} />
      </Row>
      <Row label="osd" hint="how long volume and brightness stay on screen">
        <Stepper k="feel.osdHoldMs" stops={range(400, 4000, 200)} fmt={ms} />
      </Row>
      <Row label="sound effects" hint="a short sound for a decision, a landing, a timer's end; do not disturb mutes it"><OnOff k="sound.sfx" /></Row>
      <Row label="audio bars" hint="the rail's visualiser while sound plays; its whole CPU cost">
        <Stepper k="sound.vizFps" stops={[5, 10, 15, 20, 30, 45, 60]} fmt={(n) => `${n} fps`} />
      </Row>
      <Row label="bar count" hint="bars per channel in the visualiser">
        <Stepper k="sound.vizBars" stops={[8, 12, 16, 24, 32, 48]} fmt={(n) => `${n}`} />
      </Row>
    </Panel>
  )
}

export default function Settings() {
  return (
    <window
      $={(self) => {
        win = self
        self.connect("notify::visible", syncPreview)
        // capture: Esc closes before the focused filter can take it
        self.add_controller(closeKeys({ close: () => (self.visible = false), capture: true }))
      }}
      visible={false}
      cssClasses={["settings"]}
      namespace="astal-shell-settings"
      name="settings"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.EXCLUSIVE}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.RIGHT}
      application={app}
    >
      <overlay>
        <box cssClasses={["clickaway-field"]} hexpand vexpand $={(self) => clickawayField(self, () => (win!.visible = false))} />
        <box $type="overlay" halign={Gtk.Align.CENTER} valign={Gtk.Align.START} marginTop={60}>
      <Panel title={`SETTINGS · ${PATH.replace(/^\/home\/[^/]+/, "~")}`} cssClasses={["settings-pane", "focused"]}>
        <box spacing={16}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={4} cssClasses={["set-nav"]} valign={Gtk.Align.START}>
            {SECTIONS.map((s) => <Chip label={s} on={section((c) => c === s)} onClicked={() => setSection(s)} />)}
          </box>
          <box orientation={Gtk.Orientation.VERTICAL} hexpand>
            <Backdrop />
            <Look />
            <Notifications />
            <Feel />
          </box>
        </box>
      </Panel>
        </box>
      </overlay>
    </window>
  )
}
