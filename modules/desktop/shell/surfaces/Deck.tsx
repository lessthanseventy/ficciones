// The deck: the bottom of the screen. A one-line row on every monitor — pinned attention
// (critical notices, an agent waiting on you) on the left, the command log's tail through the
// middle, now-playing (transport, a marquee title, the media card in a popover) / the timer
// (its popover) / agents on the right — and, pulled up over it (Super+C, a click on the
// activity segment), a wide drawer: the full log with source filters and the agents roster.
// A monitor showing a fullscreen window has no row.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Mpris from "gi://AstalMpris"
import Hyprland from "gi://AstalHyprland"
import { For, createBinding, createComputed, createState, type Accessor } from "ags"
import { interval, type Timer as T } from "ags/time"
import { Panel } from "../lib/tui"
import { VList } from "../lib/vlist"
import { log, hhmm, type Entry, type Src } from "../lib/log"
import { timer, left, fmtLeft, stopTimer, startCountdown, startPomodoro, parseSpec } from "../lib/timer"
import { agents } from "../lib/agents"
import { groups, dismissGroup, urgencyOf, type Group } from "./Notifications"
import { fullscreenMonitors } from "../lib/hypr"
import { MediaCard } from "../panes/Media"
import { AgentsCard } from "../panes/Agents"
import { armClickaway, disarmClickaway, closeOnPress, closeAny } from "./Clickaway"
import { hoverPopover } from "../lib/hover"

const TAIL = 2 // the activity segment: the last couple of events; the drawer has the rest
const SRCS: Src[] = ["shell", "notice", "agent", "hypr", "journal", "sys"]

// ── shared derived state ──────────────────────────────────────────────────────────────────
// lazily: Notifications imports Hub imports Deck, so `groups` is not bound at our load time
let _critical: Accessor<Group[]> | null = null
const critical = () => (_critical ??= groups((gs) => gs.filter((g) => urgencyOf(g.head) === "critical")))
const mpris = Mpris.get_default()
const players = createBinding(mpris, "players")
type Now = { p: Mpris.Player; title: string; artist: string; playing: boolean } | null
/** what to show: the playing player first, else the first with a title; re-picked on any change */
const [nowPlaying, setNow] = createState<Now>(null)
const hooked = new WeakSet<Mpris.Player>()
function pick() {
  const ps = players.peek()
  const p = ps.find((x) => x.playbackStatus === Mpris.PlaybackStatus.PLAYING) ?? ps.find((x) => x.title) ?? null
  setNow(p ? { p, title: p.title ?? "", artist: p.artist ?? "", playing: p.playbackStatus === Mpris.PlaybackStatus.PLAYING } : null)
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
// the title as a marquee when it is longer than the cell: a window that slides every 300 ms
const TRACK_W = 36
const [slide, setSlide] = createState(0)
let slider: T | null = null
const trackText = createComputed([nowPlaying, slide], (n, off) => {
  if (!n) return ""
  const s = [n.title, n.artist].filter(Boolean).join(" — ")
  if (s.length <= TRACK_W) return s
  const loop = `${s}   ·   `
  const d = loop + loop
  return d.slice(off % loop.length, (off % loop.length) + TRACK_W)
})
nowPlaying.subscribe(() => {
  const n = nowPlaying.peek()
  const long = !!n && [n.title, n.artist].filter(Boolean).join(" — ").length > TRACK_W
  if (long && n?.playing) { slider ??= interval(300, () => setSlide((x) => x + 1)) }
  else { slider?.cancel(); slider = null; setSlide(0) }
})

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

let agentsBtn: Gtk.MenuButton | null = null
/** Pop the roster (the TODAY card's "agents await you" line, `astal-shell show drawer agents`). */
export const popAgents = () => agentsBtn?.popup()

// ── the row ───────────────────────────────────────────────────────────────────────────────
export function DeckRow({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  const tail = log((l) => l.slice(-TAIL))
  const crit = critical()
  // the one toggle for the drawer: closeOnPress leaves the log alone (see Clickaway), so a
  // press here closes an open drawer, or closes any other panel and opens the drawer
  const click = new Gtk.GestureClick({ button: 1 })
  click.connect("pressed", () => { if (deckVisible()) hideDeck(); else { closeAny(); showDeck(gdkmonitor) } })
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
      {/* like the rail and bar: a press here closes whatever panel is open (the drawer, the hub) */}
      <box cssClasses={["deck-row"]} spacing={0} $={(self) => closeOnPress(self)}>
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
        {/* the log's tail, newest on the right */}
        <box cssClasses={["deck-log"]} spacing={14} hexpand $={(self) => self.add_controller(click)}>
          <For each={tail} id={(e) => e.id}>{(e) => <Line e={e} />}</For>
        </box>
        {/* ambient cells */}
        {/* now playing: transport in the cell, the title marquees when long, the media card in a popover */}
        <box cssClasses={["cell", "deck-media"]} spacing={6} visible={nowPlaying((p) => !!p)}>
          <button cssClasses={["tp"]} onClicked={() => nowPlaying.peek()?.p.previous()} visible={nowPlaying((n) => !!n?.p.canGoPrevious)}><label label="⏮" /></button>
          <button cssClasses={["tp"]} onClicked={() => nowPlaying.peek()?.p.play_pause()}><label label={nowPlaying((p) => (p?.playing ? "⏸" : "▶"))} /></button>
          <button cssClasses={["tp"]} onClicked={() => nowPlaying.peek()?.p.next()} visible={nowPlaying((n) => !!n?.p.canGoNext)}><label label="⏭" /></button>
          <menubutton cssClasses={["clickable", "deck-title"]} direction={Gtk.ArrowType.UP} $={(self) => hoverPopover(self, "deck")}>
            <label cssClasses={["deck-track"]} label={trackText} widthChars={TRACK_W} maxWidthChars={TRACK_W} xalign={0} />
            <popover cssClasses={["pop", "mediapop"]} $={(self) => { self.connect("show", () => setMediaShown(++mediaPops > 0)); self.connect("hide", () => setMediaShown((mediaPops = Math.max(0, mediaPops - 1)) > 0)) }}>
              <Panel title={"\u{f075a}  MEDIA"} cssClasses={["card", "card-media"]}><MediaCard /></Panel>
            </popover>
          </menubutton>
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
        {/* the Tlön roster (from the rail, 2026-09-07): warm/total, pink with a ! when someone awaits you */}
        <menubutton cssClasses={agents((a) => ["cell", "deck-agents", "clickable", ...(a.awaiting > 0 ? ["await"] : [])])} direction={Gtk.ArrowType.UP} $={(self) => { agentsBtn = self; hoverPopover(self, "deck") }}>
          <box spacing={6}>
            <label cssClasses={["pink"]} label={"\u{f06a9}"} />
            <label cssClasses={["pink"]} label={agents((a) => (!a.ok ? "down" : a.awaiting > 0 ? `${a.awaiting}!` : `${a.roster.filter((r) => r.warm).length}/${a.roster.length}`))} />
          </box>
          <popover cssClasses={["pop"]}>
            <Panel title={"\u{f06a9}  AGENTS"} cssClasses={["card", "card-agents"]}><AgentsCard /></Panel>
          </popover>
        </menubutton>
      </box>
    </window>
  )
}

// ── the drawer ────────────────────────────────────────────────────────────────────────────
let deckWin: Astal.Window | null = null
export const [deckOpen, setDeckOpen] = createState(false)
/** a media popover is up somewhere — the card's live capture runs only then */
export const [mediaShown, setMediaShown] = createState(false)
let mediaPops = 0

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
      {/* a real scrollbar with its own column, not the overlay one that fades in over the counts */}
      <scrolledwindow cssClasses={["history"]} hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.ALWAYS} overlayScrolling={false} vexpand>
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
      // no bottom margin: while the drawer is up Hyprland routes no pointer input to the other
      // layers, so the window reaches down over the row and its clickaway field takes the
      // press there — a second click on the row closes (2026-09-07)
      anchor={Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.TOP}
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
          <Panel title={"\u{f06a9}  AGENTS"} cssClasses={["card", "card-agents"]}><AgentsCard /></Panel>
        </box>
        <box cssClasses={["clickaway-field", "deck-rowfield"]} heightRequest={36} $={(self) => { const g = new Gtk.GestureClick({ button: 0 }); g.connect("pressed", () => hideDeck()); self.add_controller(g) }} />
      </box>
    </window>
  )
}
