import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import GLib from "gi://GLib?version=2.0"
import Battery from "gi://AstalBattery"
import Network from "gi://AstalNetwork"
import Wp from "gi://AstalWp"
import Hyprland from "gi://AstalHyprland"
import Pango from "gi://Pango?version=1.0"
import { createBinding, createComputed, createState, onCleanup } from "ags"
import { createPoll } from "ags/time"
import { focusedClient } from "../lib/hypr"
import { Stat } from "../lib/tui"
import { pct, meter } from "../lib/format"

function Title() {
  // focusedClient re-fires on focus change only; a window retitling itself (a terminal's cwd,
  // a browser tab) needs the client's own notify::title, re-hooked on every focus change.
  const [title, setTitle] = createState("")
  let hook: { c: Hyprland.Client; id: number } | null = null
  const follow = (c: Hyprland.Client | null) => {
    if (hook) hook.c.disconnect(hook.id)
    hook = c ? { c, id: c.connect("notify::title", () => setTitle(c.title ?? "")) } : null
    setTitle(c?.title ?? "")
  }
  follow(focusedClient.get())
  const unsub = focusedClient.subscribe(() => follow(focusedClient.get()))
  onCleanup(() => { unsub(); follow(null) })

  const classes = title((t) => ["title", ...(t ? [] : ["empty"])])
  const text = title((t) => t || "— no window —")
  return <label cssClasses={classes} label={text} ellipsize={Pango.EllipsizeMode.END} maxWidthChars={80} xalign={0} />
}

function Clock() {
  const time = createPoll("", 1000, () => GLib.DateTime.new_now_local().format("%H:%M")!)
  const date = createPoll("", 60_000, () => GLib.DateTime.new_now_local().format("%a %d %b")!)
  return (
    <box cssClasses={["clock"]}>
      <label label={time} />
      <label cssClasses={["date"]} label={date} />
    </box>
  )
}

function Status() {
  const bat = Battery.get_default()
  const net = Network.get_default()
  const wp = Wp.get_default()

  const batText = createComputed(
    [createBinding(bat, "percentage"), createBinding(bat, "charging")],
    (p, c) => `${pct(p)}${c ? "⚡" : ""}`,
  )
  const batClass = createBinding(bat, "percentage")((p) => ["stat", ...(p < 0.15 ? ["low"] : [])])

  const netText = createComputed(
    [createBinding(net, "primary"), createBinding(net, "wifi"), createBinding(net, "wired")],
    (primary, wifi, wired) => {
      if (primary === Network.Primary.WIFI && wifi) return `${meter(wifi.strength / 100)} ${wifi.ssid ?? ""}`
      if (primary === Network.Primary.WIRED && wired) return "eth"
      return "down"
    },
  )

  const speaker = wp?.defaultSpeaker
  const volText = speaker
    ? createComputed(
        [createBinding(speaker, "volume"), createBinding(speaker, "mute")],
        (v, m) => (m ? "mute" : meter(v)),
      )
    : "n/a"

  return (
    <box cssClasses={["status"]} spacing={18} halign={Gtk.Align.END}>
      <Stat k="NET" v={netText} />
      <Stat k="VOL" v={volText} />
      {bat.isPresent && <Stat k="BAT" v={batText} cssClasses={batClass} />}
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
        <box $type="start"><Title /></box>
        <box $type="center"><Clock /></box>
        <box $type="end" halign={Gtk.Align.END} hexpand={false}><Status /></box>
      </centerbox>
    </window>
  )
}
