// tlon's alerts, by level (lib/alerts.ts): sticky cards at the head of the toast column, info
// toasts under them that go by on their own, a
// decision banner at the top centre — one at a time, "later" folds it into the bar's pill — and
// an alarm over every monitor, a film included, for a meeting about to start.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import { For, With, createState, createComputed, onCleanup } from "ags"
import { timeout } from "ags/time"
import { Panel } from "../lib/tui"
import { closeKeys } from "../lib/keys"
import { setting } from "../lib/settings"
import { putsAway } from "../lib/alerts-core"
import { openThread, alarms, banner, stickies, infos, folded, act, dismiss, snooze, foldAway, unfold, type Alert, type Action } from "../lib/alerts"

const clock = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
const until = (iso: string) => {
  const m = Math.round((new Date(iso).getTime() - Date.now()) / 60000)
  return m > 0 ? `in ${m} min` : m === 0 ? "now" : `${-m} min ago`
}

// how many reply boxes are open: the toast column and the banner take keys only while one is — a
// layer surface that takes keys on demand can be handed the keyboard just by appearing, and then
// every toast steals the operator's typing until they switch away and back. While one is open the
// keys are its outright, so Esc works at once; Esc, Enter or any of the card's buttons closes it
// and gives them back. Counted per window: two overlay layers both exclusive fight over the
// keyboard, and a redraw of one takes it from a reply open in the other
export type Host = "toasts" | "banner"
const replies = { toasts: createState(0), banner: createState(0) }
/** the keymode for a window holding alert cards: the keyboard only while a reply is being written in it */
export const replyKeymode = (host: Host) => replies[host][0]((n) => (n > 0 ? Astal.Keymode.EXCLUSIVE : Astal.Keymode.NONE))

/** the shell's line keys in a text box: Ctrl+A/E start and end of line, Ctrl+U/K delete to them,
 * Ctrl+W the word before the cursor. True when it took the key. */
function readline(b: Gtk.TextBuffer, kv: number): boolean {
  const at = b.get_iter_at_mark(b.get_insert())
  const start = at.copy()
  start.set_line_offset(0)
  const end = at.copy()
  if (!end.ends_line()) end.forward_to_line_end()
  switch (kv) {
    case Gdk.KEY_a: b.place_cursor(start); return true
    case Gdk.KEY_e: b.place_cursor(end); return true
    case Gdk.KEY_u: b.delete(start, at); return true
    case Gdk.KEY_k: b.delete(at, end); return true
    case Gdk.KEY_w: { const word = at.copy(); word.backward_word_start(); b.delete(word, at); return true }
    default: return false
  }
}

/** an alert's actions as buttons; one taking text opens a box that grows as you write — Enter
 * sends, Shift+Enter a new line, Esc cancels, and the line keys (`readline`) edit */
function Actions({ a, host, extra = [] }: { a: Alert; host: Host; extra?: { label: string; run: () => void }[] }) {
  const setReplies = replies[host][1]
  const [asking, setAsking] = createState<Action | null>(null)
  let open = false
  const unsub = asking.subscribe(() => {
    const now = asking.peek() !== null
    if (now !== open) { open = now; setReplies((n) => n + (now ? 1 : -1)) }
  })
  onCleanup(() => { unsub(); if (open) setReplies((n) => n - 1) })
  let input: Gtk.TextView | null = null
  const typed = () => { const b = input?.buffer; return b ? b.get_text(b.get_start_iter(), b.get_end_iter(), false) : "" }
  const send = () => { const x = asking.peek(); if (x) void act(a, x, typed()); setAsking(null) }
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <box cssClasses={["actions"]} spacing={8}>
        {a.actions.map((x) => (
          <button cssClasses={["act"]} onClicked={() => { if (x.input) setAsking(x); else { setAsking(null); void act(a, x) } }}><label label={x.label} /></button>
        ))}
        {extra.map((e) => <button cssClasses={["act", "dim"]} onClicked={() => { setAsking(null); e.run() }}><label label={e.label} /></button>)}
      </box>
      <box orientation={Gtk.Orientation.VERTICAL} spacing={2} visible={asking((x) => x !== null)}>
        <label cssClasses={["dim", "sm"]} xalign={0} label={asking((x) => (x ? `${x.label.replace("…", "")} — Enter sends · Shift+Enter new line · Esc cancels · Ctrl+A/E/U/K/W` : ""))} />
        <scrolledwindow cssClasses={["alert-input"]} hscrollbarPolicy={Gtk.PolicyType.NEVER} propagateNaturalHeight maxContentHeight={240}>
          <Gtk.TextView
            wrapMode={Gtk.WrapMode.WORD_CHAR}
            acceptsTab={false}
            $={(self) => {
              input = self
              const keys = closeKeys({ close: () => setAsking(null), onKey: (kv, mods) => {
                if ((kv === Gdk.KEY_Return || kv === Gdk.KEY_KP_Enter) && !(mods & Gdk.ModifierType.SHIFT_MASK)) { send(); return true }
                return (mods & Gdk.ModifierType.CONTROL_MASK) !== 0 && readline(self.buffer, kv)
              } })
              self.add_controller(keys)
              asking.subscribe(() => { if (asking.peek()) { self.buffer.set_text("", 0); self.grab_focus() } })
            }}
          />
        </scrolledwindow>
      </box>
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
            <label selectable cssClasses={["summary"]} label={a.thread_id ? `#${a.thread_id} ${a.title}` : a.title} xalign={0} wrap maxWidthChars={44} />
            <label selectable cssClasses={["body"]} label={a.body ?? ""} visible={!!a.body} xalign={0} wrap maxWidthChars={48} />
            <Actions a={a} host="toasts" extra={[...(a.thread_id ? [{ label: "Open", run: () => openThread(a.thread_id!) }] : []), ...(putsAway(a) ? [] : [{ label: "Dismiss", run: () => dismiss(a) }])]} />
          </Panel>
        )}
      </For>
    </box>
  )
}

/** an info toast: goes by after the toast time and is dismissed for good when it does, so a key
 * shows once (the state file keeps it down across a restart while the server still lists it) */
function Info({ a }: { a: Alert }) {
  const t = timeout(Math.max(1, setting("notify.toastSeconds").peek()) * 1000, () => dismiss(a))
  onCleanup(() => t.cancel())
  return (
    <Panel title={`tlön · ${a.kind.replace("_", " ")}`} cssClasses={["toast", "alert-info"]} spacing={4}>
      <label selectable cssClasses={["summary"]} label={a.title} xalign={0} wrap maxWidthChars={44} />
      <box cssClasses={["actions"]} spacing={8} visible={!!a.thread_id}>
        <button cssClasses={["act", "dim"]} onClicked={() => { dismiss(a); void openThread(a.thread_id!) }}><label label="Open" /></button>
      </box>
    </Panel>
  )
}

/** the info toasts: under the sticky cards in the toast column */
export function Infos() {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} visible={infos((s) => s.length > 0)}>
      <For each={infos} id={(a) => a.key}>{(a: Alert) => <Info a={a} />}</For>
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
      keymode={replyKeymode("banner")}
      anchor={Astal.WindowAnchor.TOP}
      marginTop={44}
      application={app}
    >
      <With value={banner}>
        {(a: Alert | null) =>
          a && (
            <Panel title={`⚑ tlön needs a decision${a.thread_id ? ` · #${a.thread_id}` : ""}`} cssClasses={["alert-banner"]} spacing={6}>
              <label selectable cssClasses={["summary"]} label={a.title} xalign={0} wrap maxWidthChars={70} />
              <label selectable cssClasses={["body"]} label={a.body ?? ""} visible={!!a.body} xalign={0} wrap maxWidthChars={80} />
              <Actions a={a} host="banner" extra={[...(a.thread_id ? [{ label: "Open", run: () => openThread(a.thread_id!) }] : []), { label: "Later", run: () => foldAway(a) }]} />
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
        self.add_controller(closeKeys({ close: () => dismiss(a) }))
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
