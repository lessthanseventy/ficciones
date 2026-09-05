import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Pango from "gi://Pango?version=1.0"
import Battery from "gi://AstalBattery"
import Wp from "gi://AstalWp"
import { For, createBinding, createComputed, onCleanup, type Accessor } from "ags"
import { hypr, focusedClient, focusedWorkspace } from "../lib/hypr"
import PowerProfiles from "gi://AstalPowerProfiles"
import { METRICS, MetricDetail } from "../panes/Perf"
import { Visualiser } from "../lib/cava"
import Audio from "./Audio"
import { Panel } from "../lib/tui"
import Apps from "gi://AstalApps"
import { Stat, RuleV, RuleH } from "../lib/tui"
import { pct, meter, spark } from "../lib/format"
import { tier } from "../lib/perf"

/**
 * The workspace's windows, left to right as they sit in the strip: the focused one as
 * class + title, the rest as icons (click focuses). The bar's left half is theirs.
 */
function Windows({ connector }: { connector: string }) {
  const apps = new Apps.Apps()
  // This monitor's active workspace, not the globally focused one: two bars, two workspaces.
  const activeWs = () => hypr.get_monitors().find((m) => m.name === connector)?.activeWorkspace
  const iconFor = (c: Hyprland.Client) => {
    const q = apps.exact_query(c.class)[0] ?? apps.fuzzy_query(c.class)[0]
    return q?.iconName ?? "application-x-executable"
  }
  const clients = createComputed(
    [focusedWorkspace, createBinding(hypr, "clients")],
    (_, cs) => {
      const ws = activeWs()
      return cs.filter((c) => ws && c.workspace?.id === ws.id && c.mapped).sort((a, b) => a.x - b.x)
    },
  )
  return (
    <box cssClasses={["windows"]} hexpand={false}>
      <For each={clients}>
        {(c) => {
          const focused = createComputed([focusedClient], (f) => f?.address === c.address)
          const title = createBinding(c, "title")
          return (
            <button
              cssClasses={focused((f) => ["win", ...(f ? ["focused"] : [])])}
              onClicked={() => c.focus()}
              tooltipText={title}
            >
              <box spacing={8}>
                <image iconName={iconFor(c)} pixelSize={18} />
                <label cssClasses={["klass"]} label={c.class} visible={focused} />
                <label cssClasses={["title"]} label={title} visible={focused} ellipsize={Pango.EllipsizeMode.END} maxWidthChars={40} xalign={0} />
              </box>
            </button>
          )
        }}
      </For>
      <label cssClasses={["title", "empty"]} label="no window" visible={clients((cs) => cs.length === 0)} />
    </box>
  )
}

// A perf cell: icon coloured by load tier, KEY, number, an 8-glyph braille sparkline of the last
// 16 seconds; click drops the metric's detail pane straight off the cell.
const SPARK_CELLS = 8
function PerfCell({ m, icon }: { m: (typeof METRICS)[number]; icon: string }) {
  const cls = m.frac((f) => ["cell", "perf", tier(f)])
  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.DOWN} visible={m.ok ?? true}>
      <box spacing={4}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["k"]} label={m.key} />
        <label cssClasses={["num"]} label={m.num} widthChars={4} xalign={1} />
        <label cssClasses={["spark"]} label={m.hist((h) => spark(h, SPARK_CELLS))} widthChars={SPARK_CELLS} maxWidthChars={SPARK_CELLS} xalign={0} />
      </box>
      <popover cssClasses={["pop"]}>
        <Panel title={m.key}><MetricDetail m={m} /></Panel>
      </popover>
    </menubutton>
  )
}

function PerfCells() {
  const icons = ["\u{f0ee0}", "\u{f035b}", "\u{f0379}", "\u{f06f3}"]
  return (
    <box cssClasses={["perfs"]}>
      {METRICS.map((m, i) => (
        <box>
          <RuleV visible={m.ok ?? undefined} />
          <PerfCell m={m} icon={icons[i]} />
        </box>
      ))}
    </box>
  )
}

function Volume() {
  const wp = Wp.get_default()
  const speaker = wp?.defaultSpeaker
  if (!speaker) return <box cssClasses={["cell"]}><Stat k="VOL" v="n/a" /></box>
  const vol = createBinding(speaker, "volume")
  const mute = createBinding(speaker, "mute")
  const text = createComputed([vol, mute], (v, m) => (m ? "mute" : `${meter(v)} ${pct(v)}`))
  const cls = mute((m) => (m ? ["dim"] : []))
  return (
    <menubutton cssClasses={["cell", "clickable"]} direction={Gtk.ArrowType.DOWN}>
      <Stat k="VOL" v={text} cssClasses={cls} />
      <popover cssClasses={["pop"]}><Audio /></popover>
    </menubutton>
  )
}

function BatteryCell() {
  const bat = Battery.get_default()
  if (!bat.isPresent) return <box />
  const profiles = PowerProfiles.get_default()
  // The charge limit is 80%, so the bar shows charge as a share of the cap: 80% reads 100%.
  const CAP = 0.8
  const pctA = createBinding(bat, "percentage")((p) => Math.min(1, p / CAP))
  const chg = createBinding(bat, "charging")
  // Same traffic light as the perf cells: green from 50, amber to 20, red below; charging
  // always reads green.
  const cls = createComputed([pctA, chg], (p, c) => [c || p >= 0.5 ? "idle" : p >= 0.2 ? "busy" : "hot"])
  const eta = createComputed([createBinding(bat, "timeToEmpty"), createBinding(bat, "timeToFull"), chg, createBinding(bat, "energyRate")], (e, f, c, rate) => {
    const s = c ? f : e
    if (rate < 0.5 || s <= 0 || s > 48 * 3600) return c ? "charging" : "on mains"
    return `${c ? "full in" : "empty in"} ${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`
  })
  const active = createBinding(profiles, "activeProfile")
  return (
    <menubutton cssClasses={cls((c) => ["cell", "clickable", "perf", ...c])} direction={Gtk.ArrowType.DOWN}>
      <box spacing={6}>
        <label cssClasses={["icon"]} label={createComputed([pctA, chg], (p, c) => (c ? "\u{f0084}" : p > 0.6 ? "\u{f0080}" : p > 0.3 ? "\u{f007c}" : "\u{f007a}"))} />
        <Stat k="BAT" v={createComputed([pctA], (p) => `${meter(p)} ${pct(p)}`)} />
      </box>
      <popover cssClasses={["pop"]}>
        <Panel title="POWER" spacing={4}>
          <box cssClasses={["row"]} spacing={12}>
            <label label={createBinding(bat, "energyRate")((r) => `${r.toFixed(1)} W`)} />
            <label cssClasses={["dim"]} label={eta} hexpand xalign={0} />
          </box>
          <RuleH />
          {profiles.get_profiles().map(({ profile }) => (
            <button
              cssClasses={active((a) => ["row", ...(a === profile ? ["chip"] : [])])}
              onClicked={() => profiles.set_active_profile(profile)}
            >
              <label label={profile} xalign={0} hexpand />
            </button>
          ))}
        </Panel>
      </popover>
    </menubutton>
  )
}

function Status() {
  return (
    <box cssClasses={["status"]} halign={Gtk.Align.END}>
      <RuleV />
      <Volume />
      <RuleV />
      <BatteryCell />
    </box>
  )
}

export default function Bar({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  let win: Astal.Window
  const { TOP, LEFT, RIGHT } = Astal.WindowAnchor

  onCleanup(() => win.destroy())

  return (
    <window
      $={(self) => (win = self)}
      visible
      cssClasses={["bar"]}
      namespace="astal-shell-bar"
      name={`bar-${gdkmonitor.connector}`}
      gdkmonitor={gdkmonitor}
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      anchor={TOP | LEFT | RIGHT}
      application={app}
    >
      <box>
        <Windows connector={gdkmonitor.connector} />
        <box hexpand />
        <box cssClasses={["cell", "cavacell"]}><Visualiser /></box>
        <PerfCells />
        <Status />
      </box>
    </window>
  )
}
