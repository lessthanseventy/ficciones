import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Pango from "gi://Pango?version=1.0"
import { For, onCleanup, createComputed } from "ags"
import { execAsync } from "ags/process"
import { workspaces, focusedWorkspace, column } from "../lib/hypr"
import { Panel } from "../lib/tui"

function Workspaces() {
  return (
    <box cssClasses={["workspaces"]} orientation={Gtk.Orientation.VERTICAL} spacing={2}>
      <For each={workspaces}>
        {(ws) => {
          const classes = createComputed([focusedWorkspace], (f) => [
            "ws",
            ...(f?.id === ws.id ? ["focused"] : []),
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

/** Which column of the scrolling strip you occupy: one cell per column, yours lit. */
function Minimap() {
  const tape = column(([i, n]) =>
    n === 0 ? "·" : Array.from({ length: n }, (_, k) => (k === i ? "▮" : "▯")).join(""),
  )
  const pos = column(([i, n]) => (n === 0 ? "—" : `${i + 1}/${n}`))
  return (
    <box cssClasses={["minimap"]} orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.CENTER}>
      <label
        cssClasses={["tape"]}
        label={tape}
        wrap
        wrapMode={Pango.WrapMode.CHAR}
        maxWidthChars={5}
        justify={Gtk.Justification.CENTER}
      />
      <label cssClasses={["here"]} label={pos} />
    </box>
  )
}

function Power() {
  return (
    <button
      cssClasses={["power"]}
      halign={Gtk.Align.CENTER}
      onClicked={() => execAsync(["hyprctl", "dispatch", "exit"]).catch(console.error)}
    >
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
          <Panel title="WS"><Workspaces /></Panel>
          <Panel title="COL"><Minimap /></Panel>
        </box>
        <box $type="center" />
        <box $type="end" orientation={Gtk.Orientation.VERTICAL} valign={Gtk.Align.END}>
          <Power />
        </box>
      </centerbox>
    </window>
  )
}
