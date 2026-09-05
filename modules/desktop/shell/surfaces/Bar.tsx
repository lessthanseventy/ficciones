import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Pango from "gi://Pango?version=1.0"
import Battery from "gi://AstalBattery"
import Wp from "gi://AstalWp"
import { createBinding, createComputed, createState, onCleanup, type Accessor } from "ags"
import { focusedClient } from "../lib/hypr"
import { Stat, RuleV } from "../lib/tui"
import { pct, meter, spark } from "../lib/format"
import { perf, tier, rate, NET_HOT } from "../lib/perf"
import { weather, glyph } from "../lib/weather"

function Title() {
  // focusedClient re-fires on focus change only; a window retitling itself (a terminal's cwd,
  // a browser tab) needs the client's own notify::title, re-hooked on every focus change.
  const [title, setTitle] = createState("")
  const [klass, setKlass] = createState("")
  let hook: { c: Hyprland.Client; id: number } | null = null
  const follow = (c: Hyprland.Client | null) => {
    if (hook) hook.c.disconnect(hook.id)
    hook = c ? { c, id: c.connect("notify::title", () => setTitle(c.title ?? "")) } : null
    setTitle(c?.title ?? "")
    setKlass(c?.class ?? "")
  }
  follow(focusedClient.get())
  const unsub = focusedClient.subscribe(() => follow(focusedClient.get()))
  onCleanup(() => { unsub(); follow(null) })

  const classes = title((t) => ["title", ...(t ? [] : ["empty"])])
  const text = title((t) => t || "no window")
  return (
    <box cssClasses={["cell", "titlecell"]} spacing={8}>
      <label cssClasses={["klass"]} label={klass} visible={klass((k) => !!k)} />
      <label cssClasses={classes} label={text} ellipsize={Pango.EllipsizeMode.END} maxWidthChars={44} xalign={0} />
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
    <box cssClasses={cls} spacing={6} tooltipText={detail}>
      <label cssClasses={["icon"]} label={icon} />
      <label cssClasses={["k"]} label={k} />
      <label cssClasses={["num"]} label={v} widthChars={4} xalign={1} />
      <label cssClasses={["spark"]} label={line} widthChars={SPARK_CELLS} maxWidthChars={SPARK_CELLS} xalign={0} />
    </box>
  )
}

function PerfCells() {
  const cpu = perf((p) => p.cpu)
  const mem = perf((p) => p.mem)
  const net = perf((p) => Math.min(1, (p.rx + p.tx) / NET_HOT))
  return (
    <box cssClasses={["perfs"]}>
      <PerfCell k="CPU" icon={"\u{f0ee0}"} frac={cpu} v={cpu(pct)} hist={perf((p) => p.cpuHist)} detail={perf((p) => `load ${p.load1.toFixed(1)}`)} />
      <RuleV />
      <PerfCell k="RAM" icon={"\u{f035b}"} frac={mem} v={mem(pct)} hist={perf((p) => p.memHist)} detail={perf((p) => `${p.memUsedGb.toFixed(1)}/${p.memTotalGb.toFixed(0)}G`)} />
      <RuleV />
      <PerfCell k="NET" icon={"\u{f06f3}"} frac={net} v={perf((p) => rate(p.rx + p.tx))} hist={perf((p) => p.netHist)} detail={perf((p) => `\u{2193}${rate(p.rx)} \u{2191}${rate(p.tx)}`)} />
      <RuleV />
    </box>
  )
}

function WeatherCell() {
  const text = weather((w) =>
    w.ok && w.temp !== undefined
      ? `${glyph(w.code)} ${Math.round(w.temp)}° ${Math.round(w.low ?? 0)}–${Math.round(w.high ?? 0)}${w.note === "stale" ? " ·stale" : ""}`
      : `· ${w.note ?? "no weather"}`,
  )
  const cls = weather((w) => ["cell", "weather", ...(w.ok ? [] : ["dim"])])
  return (
    <box cssClasses={cls}>
      <label label={text} ellipsize={Pango.EllipsizeMode.END} maxWidthChars={40} />
    </box>
  )
}

function Status() {
  const bat = Battery.get_default()
  const wp = Wp.get_default()

  const batText = createComputed(
    [createBinding(bat, "percentage"), createBinding(bat, "charging")],
    (p, c) => `${meter(p)} ${pct(p)}${c ? "\u{f0084}" : ""}`,
  )
  // green = the highlight for "live": charging reads green, a low battery red, else body amber
  const batClass = createComputed(
    [createBinding(bat, "percentage"), createBinding(bat, "charging")],
    (p, c) => (c ? ["live"] : p < 0.15 ? ["low"] : []),
  )

  const speaker = wp?.defaultSpeaker
  const volText = speaker
    ? createComputed(
        [createBinding(speaker, "volume"), createBinding(speaker, "mute")],
        (v, m) => (m ? "mute" : `${meter(v)} ${pct(v)}`),
      )
    : "n/a"

  return (
    <box cssClasses={["status"]} halign={Gtk.Align.END}>
      <RuleV />
      <box cssClasses={["cell", "clickable"]}><Stat k="VOL" v={volText} /></box>
      {bat.isPresent && <RuleV />}
      {bat.isPresent && <box cssClasses={["cell", "clickable"]}><Stat k="BAT" v={batText} cssClasses={batClass} /></box>}
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
        <Title />
        <RuleV />
        <PerfCells />
        <box hexpand />
        <WeatherCell />
        <Status />
      </box>
    </window>
  )
}
