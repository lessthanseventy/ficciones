// tlon's alerts, by level (lib/alerts.ts): sticky cards at the head of the toast column, a
// decision banner at the top centre — one at a time, "later" folds it into the bar's pill — and
// an alarm over every monitor, a film included, for a meeting about to start.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import { For, With, createState, createComputed, onCleanup } from "ags"
import { Panel } from "../lib/tui"
import { openInOffice } from "../lib/agents"
import { alarms, banner, stickies, folded, act, dismiss, snooze, foldAway, unfold, type Alert, type Action } from "../lib/alerts"

const clock = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
const until = (iso: string) => {
  const m = Math.round((new Date(iso).getTime() - Date.now()) / 60000)
  return m > 0 ? `in ${m} min` : m === 0 ? "now" : `${-m} min ago`
}

/** an alert's actions as buttons; one taking text opens an entry, and Enter sends it */
function Actions({ a, extra = [] }: { a: Alert; extra?: { label: string; run: () => void }[] }) {
  const [asking, setAsking] = createState<Action | null>(null)
  let entry: Gtk.Entry | null = null
  const send = () => { const x = asking.peek(); if (x) void act(a, x, entry?.text ?? ""); setAsking(null) }
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <box cssClasses={["actions"]} spacing={8}>
        {a.actions.map((x) => (
          <button cssClasses={["act"]} onClicked={() => (x.input ? setAsking(x) : void act(a, x))}><label label={x.label} /></button>
        ))}
        {extra.map((e) => <button cssClasses={["act", "dim"]} onClicked={e.run}><label label={e.label} /></button>)}
      </box>
      <entry
        visible={asking((x) => x !== null)}
        placeholderText={asking((x) => (x ? `${x.label.replace("…", "")} — Enter sends, Esc cancels` : ""))}
        $={(self) => {
          entry = self
          self.connect("activate", send)
          const keys = new Gtk.EventControllerKey()
          keys.connect("key-pressed", (_, kv) => { if (kv === Gdk.KEY_Escape) { setAsking(null); return true } return false })
          self.add_controller(keys)
          asking.subscribe(() => { if (asking.peek()) { self.text = ""; self.grab_focus() } })
        }}
      />
    </box>
  )
}

/** the sticky cards: at the head of the toast column (surfaces/Notifications.tsx) */
export function Stickies() {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} visible={stickies((s) => s.length > 0)}>
      <For each={stickies} id={(a) => a.key}>
        {(a: Alert) => (
          <Panel title={`tlön · ${a.kind.replace("_", " ")}`} cssClasses={["toast", "alert-sticky"]} spacing={4}>
            <label cssClasses={["summary"]} label={a.thread_id ? `#${a.thread_id} ${a.title}` : a.title} xalign={0} wrap maxWidthChars={44} />
            <label cssClasses={["body"]} label={a.body ?? ""} visible={!!a.body} xalign={0} wrap maxWidthChars={48} />
            <Actions a={a} extra={[...(a.thread_id ? [{ label: "Open", run: () => openInOffice(a.thread_id!) }] : []), { label: "Dismiss", run: () => dismiss(a) }]} />
          </Panel>
        )}
      </For>
    </box>
  )
}

/** the decision banner: top centre, one at a time, the focused monitor's */
export function DecisionBanner() {
  let win: Astal.Window
  onCleanup(() => win.destroy())
  return (
    <window
      $={(self) => (win = self)}
      visible={banner((b) => b !== null)}
      cssClasses={["alert-banner-win"]}
      namespace="astal-shell-decision"
      name="decision"
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.ON_DEMAND}
      anchor={Astal.WindowAnchor.TOP}
      marginTop={44}
      application={app}
    >
      <With value={banner}>
        {(a: Alert | null) =>
          a && (
            <Panel title={`⚑ tlön needs a decision${a.thread_id ? ` · #${a.thread_id}` : ""}`} cssClasses={["alert-banner"]} spacing={6}>
              <label cssClasses={["summary"]} label={a.title} xalign={0} wrap maxWidthChars={70} />
              <label cssClasses={["body"]} label={a.body ?? ""} visible={!!a.body} xalign={0} wrap maxWidthChars={80} />
              <Actions a={a} extra={[...(a.thread_id ? [{ label: "Open", run: () => openInOffice(a.thread_id!) }] : []), { label: "Later", run: () => foldAway(a) }]} />
            </Panel>
          )
        }
      </With>
    </window>
  )
}

/** the bar's pill: decisions folded away for later; a click brings them back */
export function AlertPill() {
  return (
    <button cssClasses={["alert-pill"]} visible={folded((n) => n > 0)} tooltipText="decisions waiting on you" onClicked={unfold}>
      <label label={folded((n) => `⚑ ${n}`)} />
    </button>
  )
}

/** an alarm over one monitor: the meeting, when, and Join · Snooze · Dismiss; Esc dismisses */
function Alarm({ gdkmonitor, a }: { gdkmonitor: Gdk.Monitor; a: Alert }) {
  let win: Astal.Window
  onCleanup(() => win.destroy())
  const [tick, setTick] = createState(0)
  const timer = setInterval(() => setTick((n) => n + 1), 15_000)
  onCleanup(() => clearInterval(timer))
  const when = createComputed(() => (tick(), `${clock(a.at)} · ${until(a.at)}`))
  return (
    <window
      $={(self) => {
        win = self
        const keys = new Gtk.EventControllerKey()
        keys.connect("key-pressed", (_, kv) => { if (kv === Gdk.KEY_Escape) { dismiss(a); return true } return false })
        self.add_controller(keys)
      }}
      visible
      gdkmonitor={gdkmonitor}
      cssClasses={["alert-alarm-win"]}
      namespace="astal-shell-alarm"
      layer={Astal.Layer.OVERLAY}
      exclusivity={Astal.Exclusivity.IGNORE}
      keymode={Astal.Keymode.ON_DEMAND}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT}
      application={app}
    >
      <box cssClasses={["alert-alarm"]} orientation={Gtk.Orientation.VERTICAL} halign={Gtk.Align.CENTER} valign={Gtk.Align.CENTER} spacing={16}>
        <label cssClasses={["alarm-kicker"]} label={a.body ? `meeting · ${a.body}` : "meeting"} />
        <label cssClasses={["alarm-title"]} label={a.title} wrap maxWidthChars={40} justify={Gtk.Justification.CENTER} />
        <label cssClasses={["alarm-when"]} label={when} />
        <box cssClasses={["actions"]} spacing={12} halign={Gtk.Align.CENTER}>
          {a.actions.map((x) => <button cssClasses={["act", "big"]} onClicked={() => void act(a, x)}><label label={x.label} /></button>)}
          <button cssClasses={["act", "big"]} onClicked={() => snooze(a)}><label label="Snooze 5m" /></button>
          <button cssClasses={["act", "big", "dim"]} onClicked={() => dismiss(a)}><label label="Dismiss" /></button>
        </box>
      </box>
    </window>
  )
}

/** the current alarm on every monitor (one at a time: the soonest) */
export function Alarms({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  const first = alarms((as) => as[0] ?? null)
  return <With value={first}>{(a: Alert | null) => a && <Alarm gdkmonitor={gdkmonitor} a={a} />}</With>
}
