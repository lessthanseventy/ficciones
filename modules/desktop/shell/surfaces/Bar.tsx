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
import { showDrawer } from "./Drawer"
import { Panel } from "../lib/tui"
import Apps from "gi://AstalApps"
import { Stat, RuleV, RuleH } from "../lib/tui"
import { pct, meter, spark } from "../lib/format"
import { perf, tier, rate, NET_HOT } from "../lib/perf"

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
    <box cssClasses={["windows"]}>
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
                <label cssClasses={["title"]} label={title} visible={focused} ellipsize={Pango.EllipsizeMode.END} maxWidthChars={48} xalign={0} />
              </box>
            </button>
          )
        }}
      </For>
      <label cssClasses={["title", "empty"]} label="no window" visible={clients((cs) => cs.length === 0)} />
    </box>
  )
}

// A perf cell: icon coloured by load tier, KEY, the number, a braille sparkline of the last
// 16 seconds (2 samples per glyph). Detail rides the tooltip; the bar belongs to the window.
const SPARK_CELLS = 8
function PerfCell({ k, icon, v, frac, hist, detail }: {
  k: string
  icon: string
  v: Accessor<string>
  frac: Accessor<number>
  hist: Accessor<number[]>
  detail: Accessor<string>
}) {
  const cls = frac((f) => ["cell", "perf", tier(f)])
  const line = hist((h) => spark(h, SPARK_CELLS))
  return (
    <button cssClasses={cls} tooltipText={detail} onClicked={() => showDrawer("PERF")}>
      <box spacing={6}>
        <label cssClasses={["icon"]} label={icon} />
        <label cssClasses={["k"]} label={k} />
        <label cssClasses={["num"]} label={v} widthChars={4} xalign={1} />
        <label cssClasses={["spark"]} label={line} widthChars={SPARK_CELLS} maxWidthChars={SPARK_CELLS} xalign={0} />
      </box>
    </button>
  )
}

function PerfCells() {
  const cpu = perf((p) => p.cpu)
  const mem = perf((p) => p.mem)
  const net = perf((p) => Math.min(1, (p.rx + p.tx) / NET_HOT))
  return (
    <box cssClasses={["perfs"]}>
      <RuleV />
      <PerfCell k="CPU" icon={"\u{f0ee0}"} frac={cpu} v={cpu(pct)} hist={perf((p) => p.cpuHist)} detail={perf((p) => `load ${p.load1.toFixed(1)}`)} />
      <RuleV />
      <PerfCell k="RAM" icon={"\u{f035b}"} frac={mem} v={mem(pct)} hist={perf((p) => p.memHist)} detail={perf((p) => `${p.memUsedGb.toFixed(1)}/${p.memTotalGb.toFixed(0)}G`)} />
      <RuleV />
      <PerfCell k="NET" icon={"\u{f06f3}"} frac={net} v={perf((p) => rate(p.rx + p.tx))} hist={perf((p) => p.netHist)} detail={perf((p) => `\u{2193}${rate(p.rx)} \u{2191}${rate(p.tx)}`)} />
      <RuleV />
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
      <popover cssClasses={["pop"]}>
        <Panel title="AUDIO" spacing={6}>
          <box cssClasses={["row"]} spacing={12}>
            <label label={createBinding(speaker, "description")((d) => d || "output")} hexpand xalign={0} ellipsize={Pango.EllipsizeMode.END} maxWidthChars={30} />
            <button cssClasses={["act"]} onClicked={() => (speaker.mute = !speaker.mute)}>
              <label label={mute((m) => (m ? "unmute" : "mute"))} />
            </button>
          </box>
          <slider cssClasses={["vol"]} widthRequest={260} hexpand value={vol} onChangeValue={({ value }) => speaker.set_volume(value)} />
        </Panel>
      </popover>
    </menubutton>
  )
}

function BatteryCell() {
  const bat = Battery.get_default()
  if (!bat.isPresent) return <box />
  const profiles = PowerProfiles.get_default()
  const pctA = createBinding(bat, "percentage")
  const chg = createBinding(bat, "charging")
  const text = createComputed([pctA, chg], (p, c) => `${meter(p)} ${pct(p)}${c ? "\u{f0084}" : ""}`)
  // green = the highlight for "live": charging reads green, a low battery red, else body amber
  const cls = createComputed([pctA, chg], (p, c) => (c ? ["live"] : p < 0.15 ? ["low"] : []))
  const eta = createComputed([createBinding(bat, "timeToEmpty"), createBinding(bat, "timeToFull"), chg, createBinding(bat, "energyRate")], (e, f, c, rate) => {
    const s = c ? f : e
    if (rate < 0.5 || s <= 0 || s > 48 * 3600) return c ? "charging" : "on mains"
    return `${c ? "full in" : "empty in"} ${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`
  })
  const active = createBinding(profiles, "activeProfile")
  return (
    <menubutton cssClasses={["cell", "clickable"]} direction={Gtk.ArrowType.DOWN}>
      <Stat k="BAT" v={text} cssClasses={cls} />
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
        <PerfCells />
        <Status />
      </box>
    </window>
  )
}
