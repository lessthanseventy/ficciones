// Toasts: each notification is a pane with the app name inset, urgency on the border
// (low dim / normal amber / critical red), summary in body colour, actions as text buttons.
// Click dismisses; normal ones expire on their own, critical ones stay. Top right, under
// the bar, on every monitor's primary — the design's "notifications as bordered panels".
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Pango from "gi://Pango?version=1.0"
import Notifd from "gi://AstalNotifd"
import Hyprland from "gi://AstalHyprland"
import { For, createState, createComputed, onCleanup } from "ags"
import { hubOpen } from "./Hub"
import { timeout } from "ags/time"
import { Panel } from "../lib/tui"

const DEFAULT_MS = 6000

export const urgencyOf = (n: Notifd.Notification) =>
  n.urgency === Notifd.Urgency.CRITICAL ? "critical" : n.urgency === Notifd.Urgency.LOW ? "low" : "normal"

/** The notice as a pane: app name inset, urgency on the border, summary, body, actions. */
export function NoticeCard({ n }: { n: Notifd.Notification }) {
  const urgency = urgencyOf(n)
  const body = (n.body ?? "").replace(/<[^>]+>/g, "").trim()
  const when = new Date(n.time * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  return (
    <Panel title={`${n.appName || "notice"} · ${when}`} cssClasses={["toast", urgency]} spacing={4}>
      <button cssClasses={["toast-hit"]} onClicked={() => n.dismiss()}>
        <box spacing={10}>
          <image visible={!!n.appIcon} iconName={n.appIcon || "dialog-information"} pixelSize={24} valign={Gtk.Align.START} />
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2} hexpand>
            <label cssClasses={["summary"]} label={n.summary} xalign={0} wrap maxWidthChars={44} />
            <label cssClasses={["body"]} label={body} xalign={0} wrap maxWidthChars={48} visible={!!body} />
          </box>
        </box>
      </button>
      <box cssClasses={["actions"]} spacing={8} visible={n.get_actions().length > 0}>
        {n.get_actions().map((a) => (
          <button cssClasses={["act"]} onClicked={() => n.invoke(a.id)}><label label={a.label} /></button>
        ))}
      </box>
    </Panel>
  )
}

function Toast({ n, hide }: { n: Notifd.Notification; hide: () => void }) {
  // expiring hides the toast but keeps the notification for the hub's history; a click
  // dismisses it for good (you saw it)
  const ms = n.expireTimeout > 0 ? n.expireTimeout : urgencyOf(n) === "critical" ? 0 : DEFAULT_MS
  const t = ms > 0 ? timeout(ms, hide) : null
  onCleanup(() => t?.cancel())
  return <NoticeCard n={n} />
}

export default function Notifications() {
  let win: Astal.Window
  const notifd = Notifd.get_default()
  const [list, setList] = createState<Notifd.Notification[]>([])
  const hide = (id: number) => setList((l) => l.filter((x) => x.id !== id))
  notifd.connect("notified", (_, id) => {
    const n = notifd.get_notification(id)
    if (!n || notifd.dontDisturb) return
    // toasts follow the pointer's monitor
    const name = Hyprland.get_default().focusedMonitor?.name
    const mon = app.get_monitors().find((m) => m.connector === name)
    if (mon) win.gdkmonitor = mon
    setList((l) => [n, ...l.filter((x) => x.id !== id)])
  })
  notifd.connect("resolved", (_, id) => setList((l) => l.filter((x) => x.id !== id)))
  onCleanup(() => win.destroy())

  return (
    <window
      $={(self) => (win = self)}
      visible={createComputed([list, hubOpen], (l, h) => l.length > 0 && !h)}
      cssClasses={["notifications"]}
      namespace="astal-shell-notifications"
      name="notifications"
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT}
      marginTop={44}
      marginRight={8}
      application={app}
    >
      <box orientation={Gtk.Orientation.VERTICAL} spacing={0} widthRequest={420}>
        <For each={list}>{(n) => <Toast n={n} hide={() => hide(n.id)} />}</For>
      </box>
    </window>
  )
}
