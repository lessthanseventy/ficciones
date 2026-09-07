// Toasts: each notification is a pane with the app name inset, urgency on the border
// (low dim / normal amber / critical red), summary in body colour, actions as text buttons.
// Click dismisses; normal ones expire on their own, critical ones stay. Top right, under
// the bar, on every monitor's primary — the design's "notifications as bordered panels".
//
// Repeats collapse: notices with the same app, summary and body become ONE card with a ×N
// count (a chatty agent, a mail poller) — the hub, the TODAY card and the toasts all read
// from the one grouped list below, so the sort and the grouping run once per change.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Notifd from "gi://AstalNotifd"
import Hyprland from "gi://AstalHyprland"
import { For, createState, createComputed, createBinding, onCleanup, type Accessor } from "ags"
import { hubOpen } from "./Hub"
import { timeout, type Timer } from "ags/time"
import { Panel } from "../lib/tui"
import { isFullscreen, fullscreenMonitors } from "../lib/hypr"

const DEFAULT_MS = 6000
const MAX_TOASTS = 5

export const urgencyOf = (n: Notifd.Notification) =>
  n.urgency === Notifd.Urgency.CRITICAL ? "critical" : n.urgency === Notifd.Urgency.LOW ? "low" : "normal"

const clean = (s: string | null | undefined) => (s ?? "").replace(/<[^>]+>/g, "").trim()

/** Identical notices folded into one: the newest is the head, `ids` are every member. */
export type Group = { key: string; head: Notifd.Notification; count: number; ids: number[] }

/** Fold a newest-first list into groups; a group sits where its newest member sat. */
export function groupNotices(ns: Notifd.Notification[]): Group[] {
  const out: Group[] = []
  const byKey = new Map<string, Group>()
  for (const n of ns) {
    const key = `${n.appName} ${n.summary} ${clean(n.body)}`
    const g = byKey.get(key)
    if (g) { g.count++; g.ids.push(n.id) }
    else { const ng = { key, head: n, count: 1, ids: [n.id] }; byKey.set(key, ng); out.push(ng) }
  }
  return out
}

const notifd = Notifd.get_default()
/** Every undismissed notice, newest first. */
export const notices: Accessor<Notifd.Notification[]> =
  createBinding(notifd, "notifications")((ns) => [...ns].sort((a, b) => b.time - a.time))
/** The same, folded — what every surface renders. */
export const groups: Accessor<Group[]> = notices(groupNotices)

export function dismissGroup(g: Group) {
  for (const id of g.ids) notifd.get_notification(id)?.dismiss()
}

const timeOf = (n: Notifd.Notification) => new Date(n.time * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })

/**
 * The notice as a pane: app name inset (with ×N when folded), urgency on the border, summary,
 * body, actions. Takes a static group or an accessor to one — the toasts hand in the latter so
 * the count ticks up in place when a repeat lands.
 */
export function NoticeCard({ g }: { g: Group | Accessor<Group> }) {
  const live = typeof g === "function" ? (g as Accessor<Group>) : null
  const first = live ? live.peek() : (g as Group)
  const n = first.head // summary/body/app are the group's key, so the first head's are final
  const urgency = urgencyOf(n)
  const body = clean(n.body)
  const title = (x: Group) => `${x.head.appName || "notice"} · ${timeOf(x.head)}${x.count > 1 ? `  ×${x.count}` : ""}`
  const dismiss = () => dismissGroup(live ? live.peek() : first)
  // freedesktop's "default" action is the click on the notice itself, and a label-less action
  // (Claude Code sends one) has no button to be — the empty outlined box (2026-09-07)
  const actions = n.get_actions().filter((a) => a.id !== "default" && a.label.trim())
  const dflt = n.get_actions().find((a) => a.id === "default")
  const hit = () => { if (dflt) n.invoke(dflt.id); dismiss() }
  return (
    <Panel title={live ? live(title) : title(first)} cssClasses={["toast", urgency]} spacing={4}>
      <button cssClasses={["toast-hit"]} onClicked={hit}>
        <box spacing={10}>
          <image visible={!!n.appIcon} iconName={n.appIcon || "dialog-information"} pixelSize={24} valign={Gtk.Align.START} />
          <box orientation={Gtk.Orientation.VERTICAL} spacing={2} hexpand>
            <label cssClasses={["summary"]} label={n.summary} xalign={0} wrap maxWidthChars={44} />
            <label cssClasses={["body"]} label={body} xalign={0} wrap maxWidthChars={48} visible={!!body} />
          </box>
        </box>
      </button>
      <box cssClasses={["actions"]} spacing={8} visible={actions.length > 0}>
        {actions.map((a) => (
          <button cssClasses={["act"]} onClicked={() => n.invoke(a.id)}><label label={a.label} /></button>
        ))}
      </box>
    </Panel>
  )
}

export default function Notifications() {
  let win: Astal.Window
  // the toast list holds raw notices; the For renders their groups, so a repeat folds into the
  // toast already up (count ticks, timer re-arms) instead of stacking a twin under it
  const [list, setList] = createState<Notifd.Notification[]>([])
  const toastGroups = list((l) => groupNotices(l).slice(0, MAX_TOASTS))
  const hide = (ids: number[]) => setList((l) => l.filter((x) => !ids.includes(x.id)))

  function Toast({ g }: { g: Group }) {
    const live = toastGroups((gs) => gs.find((x) => x.key === g.key) ?? g)
    let t: Timer | null = null
    const arm = () => {
      t?.cancel()
      const cur = live.peek()
      // expiring hides the toast but keeps the notification for the hub's history; a click
      // dismisses it for good (you saw it)
      const ms = cur.head.expireTimeout > 0 ? cur.head.expireTimeout : urgencyOf(cur.head) === "critical" ? 0 : DEFAULT_MS
      t = ms > 0 ? timeout(ms, () => hide(live.peek().ids)) : null
    }
    arm()
    let count = g.count
    const unsub = live.subscribe(() => { const c = live.peek().count; if (c !== count) { count = c; arm() } })
    onCleanup(() => { t?.cancel(); unsub() })
    return <NoticeCard g={live} />
  }

  notifd.connect("notified", (_, id) => {
    const n = notifd.get_notification(id)
    if (!n || notifd.dontDisturb) return
    // toasts follow the pointer's monitor — unless a film is on it: then the other monitor,
    // or none at all (the notice still lands in the hub's history)
    const focused = Hyprland.get_default().focusedMonitor?.name
    const name = isFullscreen(focused) ? Hyprland.get_default().get_monitors().map((m) => m.name).find((m) => !isFullscreen(m)) : focused
    const mon = app.get_monitors().find((m) => m.connector === name)
    if (!mon) return
    win.gdkmonitor = mon
    setList((l) => [n, ...l.filter((x) => x.id !== id)])
  })
  notifd.connect("resolved", (_, id) => setList((l) => l.filter((x) => x.id !== id)))
  onCleanup(() => win.destroy())

  return (
    <window
      $={(self) => (win = self)}
      // a film starting under a toast hides it too
      visible={createComputed([list, hubOpen, fullscreenMonitors], (l, h, fs) => l.length > 0 && !h && !fs.has(win?.gdkmonitor?.connector ?? ""))}
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
        <For each={toastGroups} id={(g) => g.key}>{(g) => <Toast g={g} />}</For>
      </box>
    </window>
  )
}
