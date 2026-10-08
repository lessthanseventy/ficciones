import { L, dispatch } from "../lib/hyprlua"
import { capture } from "../lib/hypr"
import { nextUp, untilText } from "../lib/nextup"
import { kbd, layoutShort } from "../lib/kbd"
import { awake } from "../lib/awake"
import Notifd from "gi://AstalNotifd"
import app from "ags/gtk4/app"
import { closeOnPress } from "./Clickaway"
import { AlertPill } from "./Alerts"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Pango from "gi://Pango?version=1.0"
import Battery from "gi://AstalBattery"
import { For, createBinding, createComputed, createState, onCleanup, type Accessor } from "ags"
import { interval, type Timer } from "ags/time"
import { hypr, focusedClient, focusedWorkspace, addr } from "../lib/hypr"
import { toggleSidecar, sidecarAddrs } from "../lib/sidecar"
import { hoverPopover } from "../lib/hover"
import PowerProfiles from "gi://AstalPowerProfiles"
import { external, brightness, setBrightness, stepBrightness } from "../lib/brightness"
import { METRICS, MetricDetail } from "../panes/Perf"
import { Panel } from "../lib/tui"
import { iconFor } from "../lib/icons"
import { RuleV, RuleH } from "../lib/tui"
import { pct, spark } from "../lib/format"
import { tier } from "../lib/perf"
import { quietOsd } from "./Osd"
import { query } from "../lib/hyprsock"

/**
 * The workspace's windows, left to right as they sit in the strip: the focused one as
 * class + title, the rest as icons (click focuses). The bar's left half is theirs.
 */
function Windows({ connector }: { connector: string }) {
  // This monitor's active workspace, not the globally focused one: two bars, two workspaces.
  const activeWs = () => hypr.get_monitors().find((m) => m.name === connector)?.activeWorkspace
  // left to right by LIVE position: AstalHyprland's cached x goes stale as the scrolling
  // layout shifts columns (and a pinned sidecar sits at the far left)
  const hyprClients = createBinding(hypr, "clients")
  const clients = createComputed(() => {
    // focus moves are triggers: the live positions below are read from hyprctl, not tracked
    focusedWorkspace(); focusedClient()
    const cs = hyprClients()
    const ws = activeWs()
    let live = new Map<string, number>()
    try { live = new Map((JSON.parse(query("j/clients")) as { address: string; at: [number, number] }[]).map((c) => [c.address.replace(/^0x/, ""), c.at[0]])) } catch { /* cached order */ }
    const x = (c: Hyprland.Client) => live.get(c.address.replace(/^0x/, "")) ?? c.x
    return cs.filter((c) => ws && c.workspace?.id === ws.id && c.mapped).sort((a, b) => x(a) - x(b))
  })
  return (
    <box cssClasses={["windows"]} hexpand={false}>
      <For each={clients}>
        {(c) => {
          const focused = focusedClient((f) => f?.address === c.address)
          const title = createBinding(c, "title")
          const width = createBinding(c, "width"), height = createBinding(c, "height"), pinned = createBinding(c, "pinned")
          const w = addr(c)
          return (
            <menubutton
              cssClasses={focused((f) => ["win", ...(f ? ["focused"] : [])])}
              direction={Gtk.ArrowType.DOWN}
              // an already-focused window just opens its menu: focuswindow on it would still scroll
              // the layout to it (Andrew, 2026-09-07)
              $={(self) => hoverPopover(self, "bar", () => { if (hypr.focusedClient?.address !== c.address) dispatch(L.focusWindow(w)) })}
            >
              <box spacing={8}>
                <image iconName={iconFor(c)} pixelSize={18} />
                <label cssClasses={["klass"]} label={c.class} visible={focused} />
                <label cssClasses={["title"]} label={title} visible={focused} ellipsize={Pango.EllipsizeMode.END} maxWidthChars={40} xalign={0} />
              </box>
              <popover cssClasses={["pop", "pop-window"]}>
                <Panel title={`\u{f05af}  ${(c.class || "window").toUpperCase()}`} cssClasses={["card", "card-window"]} spacing={4}>
                  <label cssClasses={["amber"]} label={title} xalign={0} wrap maxWidthChars={44} />
                  <box cssClasses={["kv"]} spacing={16}>
                    <label cssClasses={["dim", "sm"]} label={`pid ${c.pid}`} />
                    <label cssClasses={["dim", "sm"]} label={createBinding(c, "workspace")((w) => `ws ${w?.id ?? "?"}`)} />
                    <label cssClasses={["dim", "sm"]} label={createComputed(() => `${width()}×${height()}`)} />
                    <label cssClasses={["dim", "sm"]} label={createBinding(c, "floating")((f) => (f ? "floating" : "tiled"))} />
                    <label cssClasses={["dim", "sm"]} label={c.xwayland ? "xwayland" : "wayland"} />
                  </box>
                  <RuleH />
                  <box spacing={6} cssClasses={["winacts"]}>
                    <button cssClasses={["act"]} onClicked={() => dispatch(L.float(w))}><label label={createBinding(c, "floating")((f) => (f ? "tile" : "float"))} /></button>
                    <button cssClasses={["act"]} onClicked={() => toggleSidecar(c)}><label label={createComputed(() => (Object.values(sidecarAddrs()).includes(c.address) || pinned() ? "unpin" : "pin"))} /></button>
                    <button cssClasses={["act"]} onClicked={() => dispatch(L.fullscreen(w, "fullscreen"))}><label label="fullscreen" /></button>
                    <button cssClasses={["act"]} onClicked={() => dispatch(L.moveToWorkspace(w, "special:magic", true))}><label label="to special" /></button>
                    <box hexpand />
                    <button cssClasses={["act", "red"]} onClicked={() => dispatch(L.close(w))}><label label="close" /></button>
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
const SPARK_CELLS = 10
function PerfCell({ m, icon }: { m: (typeof METRICS)[number]; icon: string }) {
  const cls = m.frac((f) => ["cell", "perf", tier(f, m.breaks)])
  return (
    <menubutton cssClasses={cls} direction={Gtk.ArrowType.DOWN} visible={m.ok ?? true} $={(self) => hoverPopover(self, "bar")}>
      {/* icon + spark only; the number is the tooltip and the popover (Andrew, 2026-09-07) */}
      <box spacing={3} tooltipText={m.num((n) => `${m.key.toLowerCase()} ${n.trim()}`)}>
        <label cssClasses={["icon"]} label={icon} xalign={0.5} />
        <label cssClasses={["spark"]} label={m.hist((h) => spark(m.toSpark ? h.map(m.toSpark) : h, SPARK_CELLS))} widthChars={SPARK_CELLS} maxWidthChars={SPARK_CELLS} xalign={0} />
      </box>
      <popover cssClasses={["pop", "pop-perf"]}>
        <Panel title={`\u{f0e4a}  ${m.key.toUpperCase()}`} cssClasses={["card", "card-perf"]}><MetricDetail m={m} /></Panel>
      </popover>
    </menubutton>
  )
}

function PerfCells() {
  const icons = ["\u{f0ee0}", "\u{f035b}", "\u{f0379}", "\u{f06f3}", "\u{f02ca}", "\u{f050f}"]
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
  const cls = createComputed(() => { const p = pctA(), c = chg(); return [c || p >= 0.5 ? "idle" : p >= 0.2 ? "busy" : "hot"] })
  const toEmpty = createBinding(bat, "timeToEmpty"), toFull = createBinding(bat, "timeToFull"), energyRate = createBinding(bat, "energyRate")
  const eta = createComputed(() => {
    const e = toEmpty(), f = toFull(), c = chg(), rate = energyRate()
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
          label={createComputed(() => { const p = pctA(), c = chg(); return c ? "\u{f0084}" : p >= 0.95 ? "\u{f0079}" : p >= 0.5 ? "\u{f0080}" : p >= 0.2 ? "\u{f007c}" : "\u{f008e}" })}
        />
        <label cssClasses={["num"]} label={pctA(pct)} widthChars={4} xalign={1} />
      </box>
      <popover cssClasses={["pop", "pop-power"]}>
        <Panel title={"\u{f0079}  POWER"} cssClasses={["card", "card-power"]} spacing={4}>
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

/** Something is capturing the screen (a share, a recording): red, present only while it is. */
function RecCell() {
  // a clock for the elapsed time, ticking only while a capture runs
  const [now, setNow] = createState(Date.now())
  let t: Timer | null = null
  capture.subscribe(() => {
    if (capture.peek().count && !t) t = interval(1000, () => setNow(Date.now()))
    if (!capture.peek().count && t) { t.cancel(); t = null }
  })
  const elapsed = createComputed(() => {
    const c = capture(), n = now()
    if (!c.since) return ""
    const s = Math.floor((n - c.since) / 1000)
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`
  })
  return (
    <box cssClasses={["cell", "rec"]} spacing={6} visible={capture((c) => c.count > 0)} tooltipText={capture((c) => (c.who ? `the screen is being captured by ${c.who}` : "the screen is being captured"))}>
      <label cssClasses={["rec-dot"]} label="●" />
      <label cssClasses={["rec-text"]} label={capture((c) => (c.count > 1 ? `REC ×${c.count}` : "REC"))} />
      <label cssClasses={["rec-text"]} label={elapsed} />
      <label cssClasses={["rec-who"]} label={capture((c) => c.who)} visible={capture((c) => !!c.who)} ellipsize={3} maxWidthChars={18} />
    </box>
  )
}

/** The next calendar event and the time to it — the bar's centre; pink inside ten minutes. */
function NextUpCell() {
  const [now, setNow] = createState(Date.now())
  interval(15_000, () => setNow(Date.now()))
  const text = createComputed(() => { const n = nextUp(), t = now(); return (n ? `${n.title}  ·  ${untilText(n.at, t)}` : "") })
  const cls = createComputed(() => { const n = nextUp(), t = now(); return ["cell", "nextup", ...(n && n.at - t < 10 * 60_000 ? ["soon"] : [])] })
  return (
    <box cssClasses={cls} spacing={6} visible={nextUp((n) => !!n)} tooltipText={nextUp((n) => (n ? new Date(n.at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : ""))}>
      <label cssClasses={["nextup-glyph"]} label={"\u{f00ed}"} />
      <label cssClasses={["nextup-text"]} label={text} ellipsize={3} maxWidthChars={40} />
    </box>
  )
}

/** State glyphs, only when notable: caps lock, a non-default layout, dnd, the idle inhibitor. */
function StateCells() {
  const notifd = Notifd.get_default()
  const dnd = createBinding(notifd, "dontDisturb")
  const caps = kbd((k) => k.caps)
  const layout = kbd((k) => !!k.layout && layoutShort(k.layout) !== "us")
  const any = createComputed(() => { const a = caps(), b = layout(), c = dnd(), d = awake(); return a || b || c || d })
  return (
    <box cssClasses={["states"]} spacing={0}>
      <RuleV visible={any} />
      <box cssClasses={["cell", "statecell"]} spacing={3} visible={any}>
        <label cssClasses={["state", "red"]} label={"\u{f0a9b} CAPS"} visible={caps} tooltipText="caps lock is on" />
        <label cssClasses={["state", "cyan"]} label={kbd((k) => layoutShort(k.layout))} visible={layout} tooltipText={kbd((k) => k.layout)} />
        <label cssClasses={["state", "dim"]} label={"\u{f009b}"} visible={dnd} tooltipText="do not disturb" />
        <label cssClasses={["state", "amber"]} label={"\u{f0176}"} visible={awake} tooltipText="awake: idle inhibited" />
      </box>
    </box>
  )
}

function Status() {
  return (
    <box cssClasses={["status"]} halign={Gtk.Align.END}>
      <AlertPill />
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
        <Windows connector={gdkmonitor.connector ?? ""} />
        <box hexpand />
        <NextUpCell />
        <box hexpand />
        <StateCells />
        <RecCell />
        <PerfCells />
        <Status />
      </box>
    </window>
  )
}
