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
import { closeKeys } from "../lib/keys"
import { VList } from "../lib/vlist"
import { log, hhmm, logEvent, type Entry, type Src } from "../lib/log"
import { execAsync } from "ags/process"
import { timer, left, fmtLeft, stopTimer, startCountdown, startPomodoro, parseSpec } from "../lib/timer"
import { agents } from "../lib/agents"
import { groups, dismissGroup, urgencyOf, type Group } from "./Notifications"
import { fullscreenMonitors } from "../lib/hypr"
import { MediaCard } from "../panes/Media"
import { soundPids, playerSounding } from "../lib/sound"
import { AgentsCard } from "../panes/Agents"
import { armClickaway, disarmClickaway, closeOnPress, closeAny } from "./Clickaway"
import { focus, focused, cursor, cursorOf, cycleFocus, move, jump, select } from "../lib/nav"
import { threads } from "../panes/Agents"
import { hoverPopover } from "../lib/hover"
import { showOffice, toggleOffice } from "./Office"

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
// "playing" is the truth from PipeWire when the player's process is making sound, whatever
// its Mpris status says (lib/sound); the Mpris status still counts when nothing is audible yet
function pick() {
  const ps = players.peek()
  const pids = soundPids.peek()
  const playing = (x: Mpris.Player) => x.playbackStatus === Mpris.PlaybackStatus.PLAYING || playerSounding(x.busName, pids)
  const p = ps.find(playing) ?? ps.find((x) => x.title) ?? null
  setNow(p ? { p, title: p.title ?? "", artist: p.artist ?? "", playing: playing(p) } : null)
}
soundPids.subscribe(pick)
function hook() {
  for (const p of players.peek()) if (!hooked.has(p)) {
    hooked.add(p)
    for (const sig of ["notify::playback-status", "notify::title", "notify::artist", "notify::metadata"] as const) p.connect(sig, pick)
  }
  pick()
}
players.subscribe(hook)
hook()
// and a re-pick on a timer: Floorp on a streaming site advanced an episode with no property
// notify the cell saw (it sat on the old one until a restart, 2026-09-07); pick is cheap
interval(5000, pick)
// the title as a marquee when it is longer than the cell: a window that slides every 300 ms
const TRACK_W = 36
const [slide, setSlide] = createState(0)
let slider: T | null = null
const trackText = createComputed(() => {
  const n = nowPlaying(), off = slide()
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

/** Open the office rail (the TODAY card's "agents await you" line, `astal-shell show drawer agents`). */
export const popAgents = () => showOffice()

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
      visible={fullscreenMonitors((fs) => !fs.has(gdkmonitor.connector ?? ""))}
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
          <button cssClasses={["tp"]} onClicked={() => nowPlaying.peek()?.p.previous()} visible={nowPlaying((n) => !!n?.p.canGoPrevious)}><label label={"\uf048"} /></button>
          <button cssClasses={["tp"]} onClicked={() => nowPlaying.peek()?.p.play_pause()}><label label={nowPlaying((p) => (p?.playing ? "\uf04c" : "\uf04b"))} /></button>
          <button cssClasses={["tp"]} onClicked={() => nowPlaying.peek()?.p.next()} visible={nowPlaying((n) => !!n?.p.canGoNext)}><label label={"\uf051"} /></button>
          <menubutton cssClasses={["clickable", "deck-title"]} direction={Gtk.ArrowType.UP} $={(self) => hoverPopover(self, "deck")}>
            <label cssClasses={["deck-track"]} label={trackText} widthChars={TRACK_W} maxWidthChars={TRACK_W} xalign={0} />
            <popover cssClasses={["pop", "pop-media", "mediapop"]} $={(self) => { self.connect("show", () => setMediaShown(++mediaPops > 0)); self.connect("hide", () => setMediaShown((mediaPops = Math.max(0, mediaPops - 1)) > 0)) }}>
              <Panel title={"\u{f075a}  MEDIA"} cssClasses={["card", "card-media"]}><MediaCard /></Panel>
            </popover>
          </menubutton>
        </box>
        {/* the timer is always here: idle it reads "timer" and opens the presets, running it counts */}
        <menubutton cssClasses={["cell", "deck-timer", "clickable"]} direction={Gtk.ArrowType.UP} $={(self) => hoverPopover(self, "deck")}>
          <box spacing={6}>
            <label cssClasses={timer((t) => (t ? ["cyan"] : ["dim"]))} label={timer((t) => (t?.kind === "pomodoro" ? (t.phase === "work" ? "\u{f0a3d}" : "\u{f0a3b}") : t?.kind === "alarm" ? "\u{f0021}" : "\u{f051b}"))} />
            <label cssClasses={timer((t) => (t ? ["cyan"] : ["dim"]))} label={createComputed(() => { const t = timer(), s = left(); return t ? `${fmtLeft(s)}${t.kind === "pomodoro" ? ` ${t.phase} ${t.round}` : ""}` : "timer" })} />
          </box>
          <popover cssClasses={["pop", "pop-timer", "timerpop"]}>
            <Panel title={"\u{f051b}  TIMER"} cssClasses={["card", "card-timer"]}><TimerPane /></Panel>
          </popover>
        </menubutton>
        {/* the Tlön roster: warm/total, pink with a ! when someone awaits you; toggles the office rail */}
        <button cssClasses={agents((a) => ["cell", "deck-agents", "clickable", ...(a.awaiting > 0 ? ["await"] : [])])} onClicked={() => toggleOffice(gdkmonitor)}>
          <box spacing={6}>
            <label cssClasses={["pink"]} label={"\u{f06a9}"} />
            <label cssClasses={["pink"]} label={agents((a) => (!a.ok ? "down" : a.awaiting > 0 ? `${a.awaiting}!` : `${a.roster.filter((r) => r.warm).length}/${a.roster.length}`))} />
          </box>
        </button>
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

// the log's filter state and shown rows live at module level so the drawer's keys reach them:
// digits 1–6 pick a source, 0 or a = all; Enter copies the line under the cursor
// the chips are tabs — one source at a time, or all (Andrew, 2026-09-07: not opt-in filters)
const [logSel, setLogSel] = createState<Src | null>(null)
const logShown = createComputed(() => { const o = logSel(); return [...log()].reverse().filter((e) => o === null || e.src === o) })
const pickSrc = (src: Src | null) => setLogSel(src)
export function LogPane() {
  const sel = logSel, shown = logShown
  // tracked reads for the chip producers: the FILTERS pane has focus and its cursor is on chip i
  const onChip = (i: number) => focus() === "FILTERS" && cursor().FILTERS === i
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={4}>
      <box spacing={6} cssClasses={focused("FILTERS")((f) => ["deck-filters", ...(f ? ["focused"] : [])])}>
        <button cssClasses={createComputed(() => ["filter", "src-all", ...(sel() === null ? ["chip"] : ["off"]), ...(onChip(0) ? ["cursor"] : [])])} onClicked={() => pickSrc(null)}>
          <label label="all" />
        </button>
        {SRCS.map((s, i) => (
          <button cssClasses={createComputed(() => ["filter", `src-${s}`, ...(sel() === s ? ["chip"] : ["off"]), ...(onChip(i + 1) ? ["cursor"] : [])])} onClicked={() => pickSrc(s)}>
            <label label={s} />
          </button>
        ))}
        <label cssClasses={["dim", "sm"]} label={shown((l) => `${l.length}`)} hexpand xalign={1} />
      </box>
      {/* a real scrollbar with its own column, not the overlay one that fades in over the counts */}
      <scrolledwindow cssClasses={["history"]} hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.ALWAYS} overlayScrolling={false} vexpand>
        <VList items={shown} id={(e) => String(e.id)} equal={(a, b) => a.count === b.count} render={(e) => (<Line e={e} wide />) as Gtk.Widget} cursor={cursorOf("LOG")} />
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
  // closes on Esc / q or a click outside — not on the pointer leaving. The rest is lazygit:
  // Tab / Shift+Tab cycle the pane, j/k or the arrows move its cursor, g/G jump, Enter acts
  // (LOG: copy the line; AGENTS: pick the row), 1–6 pick a log source, 0 or a = all.
  // CAPTURE: the list widget under the pointer owns GTK focus and would swallow Tab, the
  // arrows and Enter before a bubble-phase handler on the window ever saw them
  const K = Gdk
  // FILTERS is the chip row (all + the sources): h/l along it, Enter picks the chip
  const count = () => { const f = focus.peek(); return f === "FILTERS" ? SRCS.length + 1 : f === "LOG" ? logShown.peek().length : threads.peek().length }
  const horizontal = () => focus.peek() === "FILTERS"
  const keys = closeKeys({ close: hideDeck, q: true, capture: true, onKey: (kv, mods) => {
    const shift = !!(mods & Gdk.ModifierType.SHIFT_MASK)
    if (kv === K.KEY_Tab || kv === K.KEY_ISO_Left_Tab) { cycleFocus(kv === K.KEY_ISO_Left_Tab || shift ? -1 : 1); return true }
    const fwd = horizontal() ? [K.KEY_l, K.KEY_Right] : [K.KEY_j, K.KEY_Down]
    const back = horizontal() ? [K.KEY_h, K.KEY_Left] : [K.KEY_k, K.KEY_Up]
    if (fwd.includes(kv)) { move(1, count()); return true }
    if (back.includes(kv)) { move(-1, count()); return true }
    if (kv === K.KEY_g) { jump(0, count()); return true }
    if (kv === K.KEY_G) { jump(count() - 1, count()); return true }
    if (kv === K.KEY_Page_Down) { move(10, count()); return true }
    if (kv === K.KEY_Page_Up) { move(-10, count()); return true }
    if (kv === K.KEY_0 || kv === K.KEY_a) { pickSrc(null); return true }
    if (kv >= K.KEY_1 && kv <= K.KEY_6) { pickSrc(SRCS[kv - K.KEY_1]); return true }
    if (kv === K.KEY_Return || kv === K.KEY_KP_Enter || kv === K.KEY_space) {
      const f = focus.peek()
      if (f === "FILTERS") { const i = cursor.peek().FILTERS; pickSrc(i === 0 ? null : SRCS[i - 1]) }
      else if (f === "LOG") {
        const e = logShown.peek()[cursor.peek().LOG]
        if (e) { execAsync(["wl-copy", `${hhmm(e.t)}  ${e.src}  ${e.text}`]).catch(() => {}); logEvent("shell", "log line copied", "dim") }
      } else select("AGENTS", cursor.peek().AGENTS)
      return true
    }
    return false
  } })
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
          <Panel title={"\u{f0a0d}  LOG"} cssClasses={focused("LOG")((f) => ["card", "card-log", ...(f ? ["focused"] : [])])} hexpand><LogPane /></Panel>
          <Panel title={"\u{f06a9}  AGENTS"} cssClasses={focused("AGENTS")((f) => ["card", "card-agents", ...(f ? ["focused"] : [])])}><AgentsCard /></Panel>
        </box>
        <box cssClasses={["keys", "deck-keys"]} spacing={12}>
          <label label="Tab pane" /><label label="j/k move · h/l along the chips" /><label label="Enter act" /><label label="Esc close" />
        </box>
        <box cssClasses={["clickaway-field", "deck-rowfield"]} heightRequest={36} $={(self) => { const g = new Gtk.GestureClick({ button: 0 }); g.connect("pressed", () => hideDeck()); self.add_controller(g) }} />
      </box>
    </window>
  )
}
