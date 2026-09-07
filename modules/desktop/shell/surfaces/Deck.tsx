// The deck: the bottom of the screen. A one-line row on every monitor — pinned attention
// (critical notices, an agent waiting on you) on the left, the command log's tail through the
// middle, now-playing / timer / agents on the right — and, pulled up over it (bottom hot edge,
// Super+C, a click on the row), a wide drawer: the full log with source filters, media with
// transport, the agents roster, the timer. A monitor showing a fullscreen window has no row.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Mpris from "gi://AstalMpris"
import Hyprland from "gi://AstalHyprland"
import { For, createBinding, createComputed, createState, type Accessor } from "ags"
import { Panel } from "../lib/tui"
import { VList } from "../lib/vlist"
import { log, hhmm, type Entry, type Src } from "../lib/log"
import { timer, left, fmtLeft, stopTimer, startCountdown, startPomodoro, parseSpec } from "../lib/timer"
import { agents } from "../lib/agents"
import { groups, dismissGroup, urgencyOf, type Group } from "./Notifications"
import { fullscreenMonitors } from "../lib/hypr"
import { MediaCard } from "../panes/Media"
import { AgentsCard } from "../panes/Agents"
import { armClickaway, disarmClickaway } from "./Clickaway"
import { hoverPopover } from "../lib/hover"

const TAIL = 6
const SRCS: Src[] = ["shell", "notice", "agent", "hypr", "journal", "sys"]

// ── shared derived state ──────────────────────────────────────────────────────────────────
// lazily: Notifications imports Hub imports Deck, so `groups` is not bound at our load time
let _critical: Accessor<Group[]> | null = null
const critical = () => (_critical ??= groups((gs) => gs.filter((g) => urgencyOf(g.head) === "critical")))
const mpris = Mpris.get_default()
const players = createBinding(mpris, "players")
type Now = { title: string; artist: string; playing: boolean } | null
/** what to show: the playing player first, else the first with a title; re-picked on any change */
const [nowPlaying, setNow] = createState<Now>(null)
const hooked = new WeakSet<Mpris.Player>()
function pick() {
  const ps = players.peek()
  const p = ps.find((x) => x.playbackStatus === Mpris.PlaybackStatus.PLAYING) ?? ps.find((x) => x.title) ?? null
  setNow(p ? { title: p.title ?? "", artist: p.artist ?? "", playing: p.playbackStatus === Mpris.PlaybackStatus.PLAYING } : null)
}
function hook() {
  for (const p of players.peek()) if (!hooked.has(p)) {
    hooked.add(p)
    for (const sig of ["notify::playback-status", "notify::title", "notify::artist"]) p.connect(sig, pick)
  }
  pick()
}
players.subscribe(hook)
hook()

// ── the log line, shared by row and drawer ────────────────────────────────────────────────
function Line({ e, wide = false }: { e: Entry; wide?: boolean }) {
  // the whole line on hover — the row and the drawer both ellipsize
  const full = `${hhmm(e.t)}  ${e.src}  ${e.text}${e.count > 1 ? `  ×${e.count}` : ""}`
  return (
    <box spacing={6} cssClasses={["logline", e.level]} tooltipText={full} hasTooltip>
      <label cssClasses={["dim", "sm"]} label={hhmm(e.t)} />
      <label cssClasses={["src", `src-${e.src}`]} label={e.src} widthChars={wide ? 7 : 0} xalign={0} />
      <label cssClasses={["text"]} label={e.text} ellipsize={3} maxWidthChars={wide ? 120 : 56} xalign={0} hexpand={wide} />
      <label cssClasses={["dim", "sm"]} label={`×${e.count}`} visible={e.count > 1} />
    </box>
  )
}

// ── the row ───────────────────────────────────────────────────────────────────────────────
export function DeckRow({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  const tail = log((l) => l.slice(-TAIL))
  const crit = critical()
  const awaiting = agents((a) => a.awaiting)
  const click = new Gtk.GestureClick({ button: 1 })
  click.connect("released", () => toggleDeck(gdkmonitor))
  return (
    <window
      visible={fullscreenMonitors((fs) => !fs.has(gdkmonitor.connector))}
      cssClasses={["deck"]}
      namespace="astal-shell-deck"
      name={`deck-${gdkmonitor.connector}`}
      gdkmonitor={gdkmonitor}
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      anchor={Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT}
      application={app}
    >
      <box cssClasses={["deck-row"]} spacing={0}>
        {/* pinned: critical notices (up to 3, then +N), then an agent waiting — in their own
            box, since a For appends to whatever holds it */}
        <box cssClasses={["deck-pinned"]} spacing={0}>
        <For each={crit((gs) => gs.slice(0, 3))} id={(g: Group) => g.key}>
          {(g: Group) => (
            <button cssClasses={["seg", "crit"]} onClicked={() => dismissGroup(g)} tooltipText={`${g.head.body ?? ""}\n\nclick to clear`}>
              <box spacing={6}>
                <label cssClasses={["seg-app"]} label={g.head.appName || "notice"} />
                <label label={g.head.summary} ellipsize={3} maxWidthChars={36} />
                <label label={`×${g.count}`} visible={g.count > 1} />
                <label cssClasses={["seg-x"]} label={"\u{f0156}"} />
              </box>
            </button>
          )}
        </For>
        <button cssClasses={["seg", "crit"]} visible={crit((gs) => gs.length > 3)} onClicked={() => crit.peek().forEach(dismissGroup)} tooltipText="clear all">
          <label label={crit((gs) => `+${gs.length - 3}  clear all`)} />
        </button>
        </box>
        <button cssClasses={["seg", "pink"]} visible={awaiting((n) => n > 0)} onClicked={() => showDeck(gdkmonitor)}>
          <label label={awaiting((n) => `${n} ${n === 1 ? "agent awaits" : "agents await"} you`)} />
        </button>
        {/* the log's tail, newest on the right */}
        <box cssClasses={["deck-log"]} spacing={14} hexpand $={(self) => self.add_controller(click)}>
          <For each={tail} id={(e) => e.id}>{(e) => <Line e={e} />}</For>
        </box>
        {/* ambient cells */}
        <box cssClasses={["cell", "deck-media"]} spacing={6} visible={nowPlaying((p) => !!p)}>
          <label cssClasses={["amber"]} label={nowPlaying((p) => (p?.playing ? "▶" : "⏸"))} />
          <label cssClasses={["deck-track"]} label={nowPlaying((p) => (p ? [p.title, p.artist].filter(Boolean).join(" — ") : ""))} ellipsize={3} maxWidthChars={40} />
        </box>
        {/* the timer is always here: idle it reads "timer" and opens the presets, running it counts */}
        <menubutton cssClasses={["cell", "deck-timer", "clickable"]} direction={Gtk.ArrowType.UP} $={(self) => hoverPopover(self, "deck")}>
          <box spacing={6}>
            <label cssClasses={timer((t) => (t ? ["cyan"] : ["dim"]))} label={timer((t) => (t?.kind === "pomodoro" ? (t.phase === "work" ? "\u{f0a3d}" : "\u{f0a3b}") : t?.kind === "alarm" ? "\u{f0021}" : "\u{f051b}"))} />
            <label cssClasses={timer((t) => (t ? ["cyan"] : ["dim"]))} label={createComputed([timer, left], (t, s) => (t ? `${fmtLeft(s)}${t.kind === "pomodoro" ? ` ${t.phase} ${t.round}` : ""}` : "timer"))} />
          </box>
          <popover cssClasses={["pop", "timerpop"]}>
            <Panel title={"\u{f051b}  TIMER"} cssClasses={["card", "card-timer"]}><TimerPane /></Panel>
          </popover>
        </menubutton>
        <box cssClasses={["cell", "deck-agents"]} spacing={6} visible={agents((a) => a.ok && a.roster.length > 0)}>
          <label cssClasses={["pink"]} label={"\u{f06a9}"} />
          <label cssClasses={["pink"]} label={agents((a) => `${a.roster.filter((r) => r.warm).length}/${a.roster.length}`)} />
        </box>
      </box>
    </window>
  )
}

// ── the drawer ────────────────────────────────────────────────────────────────────────────
let deckWin: Astal.Window | null = null
export const [deckOpen, setDeckOpen] = createState(false)

export function showDeck(on?: Gdk.Monitor) {
  if (!deckWin) return
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = on ?? app.get_monitors().find((m) => m.connector === name)
  if (mon) deckWin.gdkmonitor = mon
  deckWin.keymode = Astal.Keymode.EXCLUSIVE
  deckWin.visible = true
  armClickaway(() => hideDeck())
}
export function hideDeck() {
  if (deckWin) { deckWin.visible = false; deckWin.keymode = Astal.Keymode.NONE }
  disarmClickaway()
}
export function toggleDeck(on?: Gdk.Monitor) {
  if (deckWin?.visible) hideDeck()
  else showDeck(on)
}
export const deckVisible = () => !!deckWin?.visible
export const deckMonitor = () => deckWin?.gdkmonitor?.connector

function LogPane() {
  // "all", or the sources picked — picking filters IN (Andrew, 2026-09-07); empty = all
  const [sel, setSel] = createState<Set<Src>>(new Set())
  const shown = createComputed([log, sel], (l, o) => [...l].reverse().filter((e) => o.size === 0 || o.has(e.src)))
  const toggle = (src: Src) => setSel((o) => { const n = new Set(o); n.has(src) ? n.delete(src) : n.add(src); return n })
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={4}>
      <box spacing={6} cssClasses={["deck-filters"]}>
        <button cssClasses={sel((o) => ["filter", "src-all", ...(o.size === 0 ? ["chip"] : ["off"])])} onClicked={() => setSel(new Set())}>
          <label label="all" />
        </button>
        {SRCS.map((s) => (
          <button cssClasses={sel((o) => ["filter", `src-${s}`, ...(o.has(s) ? ["chip"] : ["off"])])} onClicked={() => toggle(s)}>
            <label label={s} />
          </button>
        ))}
        <label cssClasses={["dim", "sm"]} label={shown((l) => `${l.length}`)} hexpand xalign={1} />
      </box>
      <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} vexpand>
        <VList items={shown} id={(e) => String(e.id)} equal={(a, b) => a.count === b.count} render={(e) => (<Line e={e} wide />) as Gtk.Widget} />
      </scrolledwindow>
    </box>
  )
}

function TimerPane() {
  let entry: Gtk.Entry
  const go = () => { const spec = parseSpec(entry.text); if (spec) { spec.start(); entry.text = "" } }
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <box spacing={8} visible={timer((t) => !!t)}>
        <label cssClasses={["big", "cyan"]} label={left((s) => fmtLeft(s))} />
        <box orientation={Gtk.Orientation.VERTICAL} hexpand>
          <label cssClasses={["amber"]} label={timer((t) => (t ? (t.kind === "pomodoro" ? `${t.phase} · round ${t.round}` : t.kind) : ""))} xalign={0} />
          <label cssClasses={["dim", "sm"]} label={timer((t) => t?.label ?? "")} xalign={0} />
        </box>
        <button cssClasses={["act", "red"]} onClicked={() => stopTimer()}><label label="stop" /></button>
      </box>
      <label cssClasses={["dim"]} label="no timer" visible={timer((t) => !t)} xalign={0} />
      <box spacing={6}>
        <button cssClasses={["act"]} onClicked={() => startCountdown(5 * 60)}><label label="5m" /></button>
        <button cssClasses={["act"]} onClicked={() => startCountdown(25 * 60)}><label label="25m" /></button>
        <button cssClasses={["act"]} onClicked={() => startCountdown(60 * 60)}><label label="1h" /></button>
        <button cssClasses={["act"]} onClicked={() => startPomodoro()}><label label="pomodoro" /></button>
      </box>
      <entry
        cssClasses={["deck-entry"]}
        placeholderText="25m · 1h10 · 14:30 · 9pm · pomo 50/10"
        $={(self) => { entry = self; self.connect("activate", go) }}
      />
    </box>
  )
}

export default function Deck() {
  // closes on Esc / q or a click outside — not on the pointer leaving
  const keys = new Gtk.EventControllerKey()
  keys.connect("key-pressed", (_, kv) => (kv === Gdk.KEY_Escape || kv === Gdk.KEY_q ? (hideDeck(), true) : false))
  return (
    <window
      $={(self) => {
        deckWin = self
        self.add_controller(keys)
        self.connect("notify::visible", () => setDeckOpen(self.visible))
      }}
      visible={false}
      cssClasses={["deck-drawer"]}
      namespace="astal-shell-deck-drawer"
      name="deck"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.NONE}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.TOP}
      marginBottom={36}
      marginTop={36}
      marginLeft={48}
      application={app}
    >
      <box orientation={Gtk.Orientation.VERTICAL}>
        <box
          cssClasses={["clickaway-field"]}
          hexpand
          vexpand
          $={(self) => { const g = new Gtk.GestureClick({ button: 0 }); g.connect("pressed", () => hideDeck()); self.add_controller(g) }}
        />
        <box cssClasses={["sheet", "bottom"]} spacing={12} heightRequest={400} vexpand={false} valign={Gtk.Align.END}>
          <Panel title={"\u{f0a0d}  LOG"} cssClasses={["card", "card-log"]} hexpand><LogPane /></Panel>
          <Panel title={"\u{f075a}  MEDIA"} cssClasses={["card", "card-media"]}><MediaCard /></Panel>
          <box orientation={Gtk.Orientation.VERTICAL} spacing={0}>
            <Panel title={"\u{f06a9}  AGENTS"} cssClasses={["card", "card-agents"]}><AgentsCard /></Panel>
            <Panel title={"\u{f051b}  TIMER"} cssClasses={["card", "card-timer"]}><TimerPane /></Panel>
          </box>
        </box>
      </box>
    </window>
  )
}
