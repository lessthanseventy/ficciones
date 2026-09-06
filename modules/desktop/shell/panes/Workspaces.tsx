// WORKSPACES: every workspace on every monitor, its windows as icons. Click a number to go
// there, click an icon to focus that window. The bar shows one workspace; this is all of them.
import Gtk from "gi://Gtk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { For, createBinding, createComputed } from "ags"
import { hypr, workspaces, focusedWorkspace, focusedClient } from "../lib/hypr"
import { iconFor } from "../lib/icons"

/** The workspace's windows as a strip of icons: shared with the rail's hover strip. */
export function WindowStrip({ ws, size = 22 }: { ws: Hyprland.Workspace; size?: number }) {
  const clients = createBinding(hypr, "clients")((cs) => cs.filter((c) => c.workspace?.id === ws.id && c.mapped).sort((a, b) => a.x - b.x))
  return (
    <box spacing={2} cssClasses={["strip"]}>
      <For each={clients}>
        {(c) => (
          <button cssClasses={focusedClient((f) => ["strip-win", ...(f?.address === c.address ? ["focused"] : [])])} onClicked={() => c.focus()} tooltipText={createBinding(c, "title")}>
            <image iconName={iconFor(c)} pixelSize={size} />
          </button>
        )}
      </For>
      <label cssClasses={["faint", "sm"]} label="·" visible={clients((cs) => cs.length === 0)} />
    </box>
  )
}

function Row({ ws }: { ws: Hyprland.Workspace }) {
  return (
    <box spacing={6} cssClasses={["ws-row"]}>
      <button cssClasses={focusedWorkspace((f) => ["ws-num", ...(f?.id === ws.id ? ["chip"] : [])])} onClicked={() => ws.focus()}>
        <label label={String(ws.id)} widthChars={2} />
      </button>
      <label cssClasses={["faint", "sm"]} label={createBinding(ws, "monitor")((m) => (m?.name ?? "").replace(/^e?DP-/, "D"))} widthChars={2} xalign={0} />
      <WindowStrip ws={ws} size={18} />
    </box>
  )
}

/** Two columns of workspaces, so ten fit under the clock. */
export function WorkspacesCard() {
  const left = workspaces((ws) => ws.slice(0, Math.ceil(ws.length / 2)))
  const right = workspaces((ws) => ws.slice(Math.ceil(ws.length / 2)))
  return (
    <box spacing={12}>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2}><For each={left}>{(ws) => <Row ws={ws} />}</For></box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2}><For each={right}>{(ws) => <Row ws={ws} />}</For></box>
    </box>
  )
}
