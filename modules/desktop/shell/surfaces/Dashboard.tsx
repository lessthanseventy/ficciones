// The dashboard: most of the screen, off the Aleph in the corner (Super+D, `astal-shell toggle
// dashboard`). Everything that is about the machine rather than a window: the toggles (from
// the hub), power (from the rail), the shell's own knobs, and a keys hint. Esc or a click on
// the field closes it.
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
import { AgentsCard } from "../panes/Agents"
import { MediaCard } from "../panes/Media"
import { METRICS, Cores, Top, type Metric } from "../panes/Perf"
import { topCpu, topMem } from "../lib/top"
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

/** A big square action: icon over a word. */
function Action({ icon, label, cls = [], onClick }: { icon: string; label: string; cls?: string[]; onClick: () => void }) {
  return (
    <button cssClasses={["action", ...cls]} onClicked={onClick}>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={4}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["sm"]} label={label} />
      </box>
    </button>
  )
}

function Power() {
  return (
    <box spacing={8} homogeneous>
      <Action icon={"\u{f033e}"} label="lock" onClick={() => run(["hyprlock"])} />
      <Action icon={"\u{f04b2}"} label="suspend" onClick={() => run(["systemctl", "suspend"])} />
      <Action icon={"\u{f0343}"} label="logout" cls={["red"]} onClick={() => run(["hyprctl", "dispatch", "exit"])} />
      <Action icon={"\u{f0709}"} label="reboot" cls={["red"]} onClick={() => run(["systemctl", "reboot"])} />
      <Action icon={"\u{f0425}"} label="shutdown" cls={["red"]} onClick={() => run(["systemctl", "poweroff"])} />
    </box>
  )
}

function Shell() {
  return (
    <box spacing={8} homogeneous>
      <Action icon={"\u{f030c}"} label="keys" onClick={() => { hideDashboard(); toggleCheatsheet() }} />
      <Action icon={"\u{f0450}"} label="restart shell" onClick={() => run(["bash", "-c", "sleep 0.2; pkill -x gjs; sleep 0.3; astal-shell"])} />
      <Action icon={"\u{f0453}"} label="reload hypr" onClick={() => run(["hyprctl", "reload"])} />
    </box>
  )
}

/** The big clock: time, date, how long the box has been up. */
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
      <label cssClasses={["faint", "sm"]} label={GLib.get_host_name()} xalign={0} />
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
        <Cores />
      </box>
      <RuleV />
      <box orientation={Gtk.Orientation.VERTICAL} spacing={12}>
        <Top list={topCpu} col="cpu" />
        <Top list={topMem} col="mem" />
      </box>
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
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.RIGHT}
      marginTop={36}
      marginLeft={54}
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
        <box $type="overlay" cssClasses={["board"]} orientation={Gtk.Orientation.VERTICAL} spacing={4} halign={Gtk.Align.FILL} valign={Gtk.Align.FILL} marginTop={40} marginBottom={56} marginStart={40} marginEnd={80}>
          <box spacing={16}>
            <Panel title={"\u{f0954}  NOW"} cssClasses={["card", "card-now"]}><ClockCard /></Panel>
            <Panel title={"\u{f0590}  WEATHER"} cssClasses={["card", "card-weather"]} hexpand><WeatherCard /></Panel>
            <Panel title={"\u{f00ed}  CALENDAR"} cssClasses={["card", "card-calendar"]}><CalendarCard /></Panel>
          </box>
          <box spacing={16} vexpand>
            <Panel title={"\u{f0e4a}  PERF"} cssClasses={["card", "card-perf"]} hexpand><PerfCard /></Panel>
            <Panel title={"\u{f06a9}  AGENTS"} cssClasses={["card", "card-agents"]}><AgentsCard /></Panel>
            <Panel title={"\u{f075a}  MEDIA"} cssClasses={["card", "card-media"]}><MediaCard /></Panel>
          </box>
          <box spacing={16}>
            <Panel title={"\u{f0493}  TOGGLES"} cssClasses={["card", "card-toggles"]} hexpand><Toggles perRow={5} /></Panel>
            <Panel title={"\u{f0425}  POWER"} cssClasses={["card", "card-power"]}><Power /></Panel>
            <Panel title={"\u2135  SHELL"} cssClasses={["card", "card-shell"]}><Shell /></Panel>
          </box>
          <box cssClasses={["keys"]} spacing={12}>
            <label label="Esc close" /><label label="Super+D toggle" />
          </box>
        </box>
      </overlay>
    </window>
  )
}
