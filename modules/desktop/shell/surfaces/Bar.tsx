import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import Pango from "gi://Pango?version=1.0"
import Battery from "gi://AstalBattery"
import Wp from "gi://AstalWp"
import { createBinding, createComputed, createState, onCleanup } from "ags"
import { focusedClient } from "../lib/hypr"
import { Stat, RuleV } from "../lib/tui"
import { pct, meter } from "../lib/format"
import { perf, tier, rate } from "../lib/perf"
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
      <label cssClasses={classes} label={text} ellipsize={Pango.EllipsizeMode.END} maxWidthChars={60} xalign={0} />
    </box>
  )
}

/** A perf cell: glyph coloured by load tier, then `KEY value`. */
function PerfCell({ k, icon, v, frac }: { k: string; icon: string; v: any; frac: any }) {
  const cls = frac((f: number) => ["cell", "perf", tier(f)])
  return (
    <box cssClasses={cls} spacing={6}>
      <label cssClasses={["icon"]} label={icon} />
      <Stat k={k} v={v} />
    </box>
  )
}

function PerfCells() {
  const cpu = perf((p) => p.cpu)
  const mem = perf((p) => p.mem)
  const net = perf((p) => Math.min(1, (p.rx + p.tx) / (10 * 1048576))) // 10 MB/s = hot
  return (
    <box cssClasses={["perfs"]}>
      <RuleV />
      <PerfCell k="CPU" icon={"\u{f0ee0}"} frac={cpu} v={cpu((c) => `${meter(c)} ${pct(c)}`)} />
      <RuleV />
      <PerfCell k="RAM" icon={"\u{f035b}"} frac={mem} v={perf((p) => `${meter(p.mem)} ${p.memUsedGb.toFixed(1)}G`)} />
      <RuleV />
      <PerfCell k="NET" icon={"\u{f06f3}"} frac={net} v={perf((p) => `↓${rate(p.rx)} ↑${rate(p.tx)}`)} />
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
      <centerbox>
        <box $type="start"><Title /><RuleV /></box>
        <box $type="center"><PerfCells /></box>
        <box $type="end"><WeatherCell /><Status /></box>
      </centerbox>
    </window>
  )
}
