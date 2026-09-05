import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import GLib from "gi://GLib?version=2.0"
import { For, onCleanup, createComputed } from "ags"
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import { hypr, workspaces, focusedWorkspace } from "../lib/hypr"
import { Panel } from "../lib/tui"
import TrayPane from "./Tray"
import { toggleDrawer } from "./Drawer"
import { weather, glyph } from "../lib/weather"
import { Channel } from "../lib/cava"

/** This monitor's workspaces only, its active one chipped — two monitors, two rails. */
function Workspaces({ connector }: { connector: string }) {
  const mine = createComputed([workspaces, focusedWorkspace], (all) =>
    all.filter((w) => w.monitor?.name === connector),
  )
  const active = () => hypr.get_monitors().find((m) => m.name === connector)?.activeWorkspace
  // Wheel over the pane walks this monitor's workspaces (m-1 / m+1 = same-monitor relative).
  const scroll = new Gtk.EventControllerScroll({ flags: Gtk.EventControllerScrollFlags.VERTICAL })
  scroll.connect("scroll", (_, __, dy) => {
    hypr.dispatch("workspace", dy > 0 ? "m+1" : "m-1")
    return true
  })
  return (
    <box cssClasses={["workspaces"]} orientation={Gtk.Orientation.VERTICAL} spacing={2} $={(self) => self.add_controller(scroll)}>
      <For each={mine}>
        {(ws) => {
          const classes = createComputed([focusedWorkspace], () => [
            "ws",
            ...(active()?.id === ws.id ? ["focused"] : []),
            ...(ws.get_clients().length > 0 ? ["occupied"] : []),
          ])
          return (
            <button cssClasses={classes} onClicked={() => ws.focus()} halign={Gtk.Align.CENTER}>
              <label label={String(ws.id)} />
            </button>
          )
        }}
      </For>
    </box>
  )
}

/** Stacked clock. Click toggles the drawer (the info pane) — the one big affordance. */
function Clock() {
  const now = createPoll(GLib.DateTime.new_now_local(), 1000, () => GLib.DateTime.new_now_local())
  return (
    <button cssClasses={["clock"]} onClicked={() => toggleDrawer()}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["hh"]} label={now((d) => d.format("%H")!)} />
        <label cssClasses={["mm"]} label={now((d) => d.format("%M")!)} />
        <label cssClasses={["dow"]} label={now((d) => d.format("%a")!)} />
        <label cssClasses={["day"]} label={now((d) => d.format("%d")!)} />
        <label cssClasses={["mon"]} label={now((d) => d.format("%b")!)} />
      </box>
    </button>
  )
}

/** Under the clock: the sky and the temperature, two rows. Detail is the drawer's WEATHER tab. */
function Weather() {
  const g = weather((w) => (w.ok ? glyph(w.code) : "\u{f0590}"))
  const t = weather((w) => (w.ok ? `${Math.round(w.temp!)}°` : "—"))
  const cls = weather((w) => ["wx", ...(w.ok ? [] : ["dim"])])
  return (
    <button cssClasses={cls} onClicked={() => toggleDrawer()} tooltipText={weather((w) => w.note ?? "")}>
      <box orientation={Gtk.Orientation.VERTICAL}>
        <label cssClasses={["g"]} label={g} />
        <label cssClasses={["t"]} label={t} />
      </box>
    </button>
  )
}

function Power() {
  return (
    <button cssClasses={["power"]} halign={Gtk.Align.CENTER} onClicked={() => execAsync(["hyprctl", "dispatch", "exit"]).catch(console.error)}>
      <label label="⏻" />
    </button>
  )
}

export default function Rail({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  let win: Astal.Window
  const { TOP, LEFT, BOTTOM } = Astal.WindowAnchor

  onCleanup(() => win.destroy())

  return (
    <window
      $={(self) => (win = self)}
      visible
      defaultWidth={1} // shrink to content; a GtkWindow otherwise pads its default size
      cssClasses={["rail"]}
      namespace="astal-shell-rail"
      name={`rail-${gdkmonitor.connector}`}
      gdkmonitor={gdkmonitor}
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      anchor={TOP | LEFT | BOTTOM}
      application={app}
    >
      <centerbox orientation={Gtk.Orientation.VERTICAL}>
        <box $type="start" orientation={Gtk.Orientation.VERTICAL}>
          <Panel title="WS"><Workspaces connector={gdkmonitor.connector} /></Panel>
        </box>
        <box $type="center" orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER}>
          <Channel side="left" />
          <Clock />
          <Weather />
          <Channel side="right" />
        </box>
        <box $type="end" orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.END}>
          <TrayPane />
          <Power />
        </box>
      </centerbox>
    </window>
  )
}
