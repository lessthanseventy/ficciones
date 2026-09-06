import app from "ags/gtk4/app"
import { closeOnPress } from "./Clickaway"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Pango from "gi://Pango?version=1.0"
import Battery from "gi://AstalBattery"
import { For, createBinding, createComputed, onCleanup, type Accessor } from "ags"
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import { hypr, focusedClient, focusedWorkspace, addr } from "../lib/hypr"
import { toggleSidecar } from "../lib/sidecar"
import { hoverPopover } from "../lib/hover"
import PowerProfiles from "gi://AstalPowerProfiles"
import { external, brightness, setBrightness, stepBrightness } from "../lib/brightness"
import { METRICS, MetricDetail } from "../panes/Perf"
import { MediaCard } from "../panes/Media"
import { Visualiser } from "../lib/cava"
import { Panel } from "../lib/tui"
import { iconFor } from "../lib/icons"
import { Stat, RuleV, RuleH } from "../lib/tui"
import { pct, meter, spark } from "../lib/format"
import { tier } from "../lib/perf"
import { quietOsd } from "./Osd"

/**
 * The workspace's windows, left to right as they sit in the strip: the focused one as
 * class + title, the rest as icons (click focuses). The bar's left half is theirs.
 */
function Windows({ connector }: { connector: string }) {
  // This monitor's active workspace, not the globally focused one: two bars, two workspaces.
  const activeWs = () => hypr.get_monitors().find((m) => m.name === connector)?.activeWorkspace
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
          const d = (cmd: string, arg = "") => hypr.dispatch(cmd, `${arg} ${addr(c)}`.trim())
          return (
            <menubutton
              cssClasses={focused((f) => ["win", ...(f ? ["focused"] : [])])}
              direction={Gtk.ArrowType.DOWN}
              $={(self) => hoverPopover(self, "bar", () => c.focus())}
            >
              <box spacing={8}>
                <image iconName={iconFor(c)} pixelSize={18} />
                <label cssClasses={["klass"]} label={c.class} visible={focused} />
                <label cssClasses={["title"]} label={title} visible={focused} ellipsize={Pango.EllipsizeMode.END} maxWidthChars={40} xalign={0} />
              </box>
              <popover cssClasses={["pop"]}>
                <Panel title={c.class || "window"} spacing={4}>
                  <label cssClasses={["amber"]} label={title} xalign={0} wrap maxWidthChars={44} />
                  <box cssClasses={["kv"]} spacing={16}>
                    <label cssClasses={["dim", "sm"]} label={`pid ${c.pid}`} />
                    <label cssClasses={["dim", "sm"]} label={createBinding(c, "workspace")((w) => `ws ${w?.id ?? "?"}`)} />
                    <label cssClasses={["dim", "sm"]} label={createComputed([createBinding(c, "width"), createBinding(c, "height")], (w, h) => `${w}×${h}`)} />
                    <label cssClasses={["dim", "sm"]} label={createBinding(c, "floating")((f) => (f ? "floating" : "tiled"))} />
                    <label cssClasses={["dim", "sm"]} label={c.xwayland ? "xwayland" : "wayland"} />
                  </box>
                  <RuleH />
                  <box spacing={6} cssClasses={["winacts"]}>
                    <button cssClasses={["act"]} onClicked={() => d("togglefloating")}><label label={createBinding(c, "floating")((f) => (f ? "tile" : "float"))} /></button>
                    <button cssClasses={["act"]} onClicked={() => toggleSidecar(c)}><label label={createBinding(c, "pinned")((p) => (p ? "unpin" : "pin"))} /></button>
                    <button cssClasses={["act"]} onClicked={() => { c.focus(); hypr.dispatch("fullscreen", "1") }}><label label="fullscreen" /></button>
                    <button cssClasses={["act"]} onClicked={() => d("movetoworkspace", "special:magic,")}><label label="to special" /></button>
                    <box hexpand />
                    <button cssClasses={["act", "red"]} onClicked={() => d("closewindow")}><label label="close" /></button>
                  </box>
                </Panel>
              </popover>
            </menubutton>
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
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.DOWN} visible={m.ok ?? true} $={(self) => hoverPopover(self, "bar")}>
      <box spacing={4}>
        <label cssClasses={["icon"]} label={icon} tooltipText={m.key} />
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

/** The brightness slider (lib/brightness.ts picks the backend). */
function Backlight() {
  const label = external((ext) => (ext ? "\u{f0335}  brightness · software, all screens" : "\u{f00e0}  brightness · backlight"))
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      <box spacing={8}>
        <label cssClasses={["k", "sm"]} label={label} hexpand xalign={0} />
        <label cssClasses={["sm"]} label={brightness(pct)} />
      </box>
      <slider cssClasses={["vol"]} hexpand min={external((e) => (e ? 0.3 : 0))} value={brightness} onChangeValue={({ value: v }) => { quietOsd(); setBrightness(v) }} />
    </box>
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
  // click opens (not hover — Andrew, 2026-09-05); the wheel over the cell is brightness, 5 % a notch
  const scroll = new Gtk.EventControllerScroll({ flags: Gtk.EventControllerScrollFlags.VERTICAL })
  scroll.connect("scroll", (_, __, dy) => { stepBrightness(dy > 0 ? -0.05 : 0.05); return true })
  return (
    <menubutton cssClasses={cls((c) => ["cell", "clickable", "perf", ...c])} direction={Gtk.ArrowType.DOWN} $={(self) => self.add_controller(scroll)}>
      <box spacing={4}>
        <label
          cssClasses={["icon"]}
          label={createComputed([pctA, chg], (p, c) =>
            c ? "\u{f0084}" : p >= 0.95 ? "\u{f0079}" : p >= 0.5 ? "\u{f0080}" : p >= 0.2 ? "\u{f007c}" : "\u{f008e}",
          )}
        />
        <label cssClasses={["num"]} label={pctA(pct)} widthChars={4} xalign={1} />
      </box>
      <popover cssClasses={["pop"]}>
        <Panel title="POWER" spacing={4}>
          <box cssClasses={["row"]} spacing={12}>
            <label label={createBinding(bat, "energyRate")((r) => `${r.toFixed(1)} W`)} />
            <label cssClasses={["dim"]} label={eta} hexpand xalign={0} />
          </box>
          <RuleH />
          <Backlight />
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
      $={(self) => { win = self; closeOnPress(self) }}
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
        <menubutton cssClasses={["cell", "cavacell", "clickable"]} direction={Gtk.ArrowType.DOWN} $={(self) => hoverPopover(self, "bar")}>
          <Visualiser />
          <popover cssClasses={["pop", "mediapop"]}>
            <Panel title={"\u{f075a}  MEDIA"} cssClasses={["card", "card-media"]}><MediaCard /></Panel>
          </popover>
        </menubutton>
        <PerfCells />
        <Status />
      </box>
    </window>
  )
}
