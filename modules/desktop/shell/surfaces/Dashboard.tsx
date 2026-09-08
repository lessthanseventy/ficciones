// The dashboard: most of the screen, off the Aleph in the corner (Super+D, `astal-shell toggle
// dashboard`). Everything that is about the machine rather than a window: the toggles (from
// the hub), power (from the rail), the shell's own knobs. Esc or a click on
// the field closes it.
import { L, dispatch } from "../lib/hyprlua"
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { execAsync } from "ags/process"
import { Panel } from "../lib/tui"
import GLib from "gi://GLib?version=2.0"
import { createPoll } from "ags/time"
import { Toggles } from "../panes/Toggles"
import { toggleCheatsheet } from "./Cheatsheet"
import { CalendarCard } from "../panes/Calendar"
import { WeatherCard } from "../panes/Weather"
import { METRICS, CoreGrid, Procs, type Metric } from "../panes/Perf"
import { DiskCard } from "../panes/Disk"
import { NetCard } from "../panes/Net"
import { LogPane } from "./Deck"
import { WorkspacesCard } from "../panes/Workspaces"
import { RuleV } from "../lib/tui"
import { tier } from "../lib/perf"
import { meter, spark } from "../lib/format"

let win: Astal.Window | null = null
export const dashboardOpen = () => !!win?.visible
export function hideDashboard() { if (win) win.visible = false }
export function showDashboard() {
  if (!win) return
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (mon) win.gdkmonitor = mon
  win.visible = true
}
export const toggleDashboard = () => (dashboardOpen() ? hideDashboard() : showDashboard())

const run = (cmd: string[]) => { hideDashboard(); execAsync(cmd).catch(console.error) }

/** An action as a row: icon, then the word. The POWER and SHELL cards are lists of these. */
function Action({ icon, label, cls = [], onClick, tile = false }: { icon: string; label: string; cls?: string[]; onClick: () => void; tile?: boolean }) {
  // a tile: the icon over the word, the toggles' shape — for the rows that must stay narrow
  if (tile) return (
    <button cssClasses={["toggle", "tile", ...cls]} onClicked={onClick}>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["sm"]} label={label} />
      </box>
    </button>
  )
  return (
    <button cssClasses={["action", ...cls]} onClicked={onClick}>
      <box spacing={10}>
        <label cssClasses={["icon"]} label={icon} widthChars={2} />
        <label cssClasses={["sm"]} label={label} xalign={0} hexpand />
      </box>
    </button>
  )
}

function Power() {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={4} cssClasses={["tiles"]}>
      <box spacing={4} homogeneous>
        <Action icon={"\u{f033e}"} label="lock" tile onClick={() => run(["hyprlock"])} />
        <Action icon={"\u{f04b2}"} label="suspend" tile onClick={() => run(["systemctl", "suspend"])} />
        <Action icon={"\u{f0343}"} label="logout" tile cls={["red"]} onClick={() => dispatch(L.exit())} />
      </box>
      <box spacing={4} homogeneous>
        <Action icon={"\u{f0709}"} label="reboot" tile cls={["red"]} onClick={() => run(["systemctl", "reboot"])} />
        <Action icon={"\u{f0425}"} label="shutdown" tile cls={["red"]} onClick={() => run(["systemctl", "poweroff"])} />
        <box />
      </box>
    </box>
  )
}

function Shell() {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={4} cssClasses={["tiles"]}>
      <box spacing={4} homogeneous>
        <Action icon={"\u{f030c}"} label="keys" tile onClick={() => { hideDashboard(); toggleCheatsheet() }} />
        <Action icon={"\u{f0450}"} label="restart" tile onClick={() => run(["bash", "-c", "sleep 0.2; pkill -x gjs; sleep 0.3; astal-shell"])} />
      </box>
      <box spacing={4} homogeneous>
        <Action icon={"\u{f0453}"} label="reload hypr" tile onClick={() => run(["hyprctl", "reload"])} />
        <box />
      </box>
    </box>
  )
}

/** The big clock: time, date, how long the box has been up. */
/** The mark: the corner's doubled aleph and the name, the machine under it — its own little
 * card above NOW, so the left column fills to the weather card (Andrew, 2026-09-07). */
function MarkCard() {
  return (
    <box cssClasses={["wordmark"]} spacing={12} valign={Gtk.Align.CENTER}>
      {/* the glyph inks low in its box: a nudge up centres it on the two lines of text */}
      <overlay valign={Gtk.Align.CENTER} marginBottom={6}>
        <label cssClasses={["aleph"]} label={"\u2135"} />
        <label $type="overlay" cssClasses={["hron"]} label={"\u2135"} canTarget={false} />
      </overlay>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={0} valign={Gtk.Align.CENTER}>
        <overlay>
          <label cssClasses={["name"]} label="ficciones" xalign={0} />
          <label $type="overlay" cssClasses={["name", "hron"]} label="ficciones" xalign={0} canTarget={false} />
        </overlay>
        <label cssClasses={["dim", "sm"]} label={GLib.get_host_name()} xalign={0} />
      </box>
    </box>
  )
}

function ClockCard() {
  const now = createPoll(GLib.DateTime.new_now_local(), 1000, () => GLib.DateTime.new_now_local())
  const up = createPoll("", 30_000, () => {
    try {
      const [ok, bytes] = GLib.file_get_contents("/proc/uptime")
      const s = ok ? parseFloat(new TextDecoder().decode(bytes)) : 0
      const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60)
      return `up ${d ? `${d}d ` : ""}${h}h ${m}m`
    } catch { return "" }
  })
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={2} valign={Gtk.Align.CENTER}>
      <label cssClasses={["bigtime"]} label={now((d) => d.format("%H:%M")!)} xalign={0} />
      <label cssClasses={["amber", "lg"]} label={now((d) => d.format("%A")!)} xalign={0} />
      <label cssClasses={["dim"]} label={now((d) => d.format("%-d %B %Y")!)} xalign={0} />
      <label cssClasses={["dim", "sm"]} label={up} xalign={0} />
    </box>
  )
}

/** One gauge: KEY, number, a meter, a sparkline, the detail line — coloured by load. */
function Gauge({ m }: { m: Metric }) {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} cssClasses={m.frac((f) => ["gauge", tier(f)])} spacing={2} hexpand visible={m.ok ?? true}>
      <box spacing={10}>
        <label cssClasses={["k", "lg"]} label={m.key} xalign={0} />
        <label cssClasses={["num", "lg"]} label={m.num} xalign={1} hexpand />
      </box>
      <label cssClasses={["bar"]} label={m.frac((f) => meter(f, 24))} xalign={0} />
      <label cssClasses={["spark"]} label={m.hist((h) => spark(h, 24))} xalign={0} />
      <label cssClasses={["dim", "sm"]} label={m.detail} xalign={0} />
    </box>
  )
}

/** btop, more or less: the four gauges with long sparklines, the cores, the top processes. */
function PerfCard() {
  const [cpu, ram, gpu, net] = METRICS
  return (
    <box spacing={20}>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={14} hexpand>
        <box spacing={24} homogeneous><Gauge m={cpu} /><Gauge m={ram} /></box>
        <box spacing={24} homogeneous><Gauge m={gpu} /><Gauge m={net} /></box>
        <CoreGrid />
      </box>
      <RuleV />
      <Procs />
    </box>
  )
}

export default function Dashboard() {
  return (
    <window
      $={(self) => {
        win = self
        const k = new Gtk.EventControllerKey()
        k.connect("key-pressed", (_, kv) => (kv === Gdk.KEY_Escape || kv === Gdk.KEY_q ? (hideDashboard(), true) : false))
        self.add_controller(k)
      }}
      cssClasses={["dashboard"]}
      namespace="astal-shell-dashboard"
      name="dashboard"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.ON_DEMAND}
      exclusivity={Astal.Exclusivity.IGNORE}
      // the whole monitor, rail and bar included: a click ANYWHERE outside the board closes —
      // the rail's corner too, which stopped taking a second click once this window held
      // the keyboard (its pointer crossing state went with it; Andrew, 2026-09-07)
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.RIGHT}
      application={app}
      visible={false}
    >
      {/* the field is the click-away; the board sits in it with desktop showing round it */}
      <overlay>
        <box
          cssClasses={["clickaway-field"]}
          hexpand
          vexpand
          $={(self) => {
            const g = new Gtk.GestureClick({ button: 0 })
            g.connect("pressed", () => hideDashboard())
            self.add_controller(g)
          }}
        />
        <box $type="overlay" cssClasses={["board"]} orientation={Gtk.Orientation.VERTICAL} spacing={16} halign={Gtk.Align.FILL} valign={Gtk.Align.FILL} marginTop={36 + 8} marginBottom={24 + 8} marginStart={54 + 8} marginEnd={8}>
          {/* three rows, packed to fit 1920×1080 with the rail and bar; one 16px gap between every
              pair of outer frames and from the board's edge (the card margin equals its outline
              offset, so the box spacing IS the gap). No key hints under the cards: the even
              gaps cost the height they took; Esc / Super+D are in the cheatsheet */}
          <box spacing={16}>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={16} hexpand>
          <box spacing={16}>
            <box orientation={Gtk.Orientation.VERTICAL} spacing={16}>
              <Panel title={"\u2135  FICCIONES"} cssClasses={["card", "card-mark"]}><MarkCard /></Panel>
              <Panel title={"\u{f0954}  NOW"} cssClasses={["card", "card-now"]}><ClockCard /></Panel>
              <Panel title={"\u{f0771}  WORKSPACES"} cssClasses={["card", "card-workspaces"]}><WorkspacesCard /></Panel>
            </box>
            {/* weather is short (the week as columns) so the calendar column sets row one's height
                and TODAY, the agenda, takes what is left of it (Andrew, 2026-09-07) */}
            <Panel title={"\u{f0590}  WEATHER"} cssClasses={["card", "card-weather"]} hexpand><WeatherCard compact /></Panel>
          </box>
          <box spacing={16}>
            <Panel title={"\u{f0e4a}  PERF"} cssClasses={["card", "card-perf"]} hexpand><PerfCard /></Panel>
          </box>
          </box>
          {/* the right column spans both rows: the calendar fills down (the agenda goes in it once
              there are calendars), DISK and NET sit level with PERF's bottom (Andrew, 2026-09-07) */}
          <box orientation={Gtk.Orientation.VERTICAL} spacing={16}>
            <Panel title={"\u{f00ed}  CALENDAR"} cssClasses={["card", "card-calendar"]} vexpand><CalendarCard /></Panel>
            <Panel title={"\u{f02ca}  DISK"} cssClasses={["card", "card-disk"]}><DiskCard /></Panel>
            <Panel title={"\u{f05a9}  NET"} cssClasses={["card", "card-net"]}><NetCard /></Panel>
          </box>
          </box>
          <box spacing={16} vexpand>
            {/* the deck's log, filters and all — not the journal alone (Andrew, 2026-09-07) */}
            <Panel title={"\u{f0a0d}  LOG"} cssClasses={["card", "card-log"]} hexpand vexpand><LogPane /></Panel>
            <Panel title={"\u{f0493}  TOGGLES"} cssClasses={["card", "card-toggles"]}><Toggles perRow={5} omit={["profile"]} /></Panel>
            <Panel title={"\u{f0425}  POWER"} cssClasses={["card", "card-power"]}><Power /></Panel>
            <Panel title={"\u2135  SHELL"} cssClasses={["card", "card-shell"]}><Shell /></Panel>
          </box>
        </box>
      </overlay>
    </window>
  )
}
