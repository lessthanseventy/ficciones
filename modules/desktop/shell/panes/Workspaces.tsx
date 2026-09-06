// WORKSPACES: every workspace on every monitor, its windows as icons. Click a number to go
// there, click an icon to focus that window. The bar shows one workspace; this is all of them.
import Gtk from "gi://Gtk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { For, createBinding, createComputed } from "ags"
import { hypr, workspaces, focusedWorkspace, focusedClient } from "../lib/hypr"
import { iconFor } from "../lib/icons"
import Gio from "gi://Gio?version=2.0"
import { stamp, hasThumb, pathFor, geom } from "../lib/thumbs"

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
const THUMB_H = 140

/**
 * The rail's hover strip for a workspace number: the windows as a literal strip of thumbnails
 * (lib/thumbs.ts), each captioned with its class, click to focus. A window never captured
 * (opened on a workspace that has not been shown since) falls back to its icon.
 */
export function WorkspacePop({ ws }: { ws: Hyprland.Workspace }) {
  const clients = createBinding(hypr, "clients")((cs) => cs.filter((c) => c.workspace?.id === ws.id && c.mapped).sort((a, b) => a.x - b.x))
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={4}>
      <box spacing={8} cssClasses={["thumbs"]}>
        <For each={clients}>
          {(c) => {
            const file = stamp(() => (hasThumb(c.address) ? Gio.File.new_for_path(pathFor(c.address)) : null))
            const w = stamp(() => { const g = geom.get(c.address); return Math.max(80, Math.min(320, Math.round((THUMB_H * (g?.w ?? c.width)) / Math.max(1, g?.h ?? c.height)))) })
            return (
              <button cssClasses={focusedClient((f) => ["thumb", ...(f?.address === c.address ? ["focused"] : [])])} onClicked={() => c.focus()} tooltipText={createBinding(c, "title")}>
                <box orientation={Gtk.Orientation.VERTICAL} spacing={2}>
                  <overlay>
                    <box cssClasses={["shot"]} widthRequest={w} heightRequest={THUMB_H}>
                      <Gtk.Picture file={file} contentFit={Gtk.ContentFit.CONTAIN} hexpand vexpand visible={file((f) => !!f)} />
                      <image iconName={iconFor(c)} pixelSize={48} hexpand vexpand halign={Gtk.Align.CENTER} valign={Gtk.Align.CENTER} visible={file((f) => !f)} />
                    </box>
                    <box $type="overlay" halign={Gtk.Align.START} valign={Gtk.Align.END} spacing={4} cssClasses={["cap"]} canTarget={false}>
                      <image iconName={iconFor(c)} pixelSize={14} />
                      <label cssClasses={["sm"]} label={c.class} ellipsize={3} maxWidthChars={16} />
                    </box>
                  </overlay>
                </box>
              </button>
            )
          }}
        </For>
      </box>
      <label cssClasses={["dim"]} label="empty" visible={clients((cs) => cs.length === 0)} xalign={0} />
    </box>
  )
}

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
