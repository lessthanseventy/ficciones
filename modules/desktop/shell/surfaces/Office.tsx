// The office: a rail on the right (the deck's board cell toggles it, `astal-shell toggle office`)
// listing the Claudes running, your move first, then babylon's board in a line and its open asks.
// A row takes you to that Claude's pane in arena; an ask takes you to arena, where the board is.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { For, createComputed } from "ags"
import { sessions, readAt, rows, rowLines, goTo, goToArena, type Row } from "../lib/sessions"
import { board, asking, held, boardLine, type Card } from "../lib/board"
import { Panel, RuleH } from "../lib/tui"
import { closeKeys } from "../lib/keys"
import { armClickaway, closeAny, disarmClickaway, clickawayField } from "./Clickaway"

const ROW_CHARS = 44
const shown = createComputed(() => { const b = board(); return rows(sessions(), (s) => held(b, s)) })
const asks = board(asking)

let officeWin: Astal.Window | null = null
export function showOffice(on?: Gdk.Monitor) {
  if (!officeWin) return
  closeAny()
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = on ?? app.get_monitors().find((m) => m.connector === name)
  if (mon) officeWin.gdkmonitor = mon
  // the keyboard while it is up, like the hub: it is a click-away sheet, not a place to type past
  officeWin.keymode = Astal.Keymode.EXCLUSIVE
  officeWin.visible = true
  armClickaway(() => hideOffice())
}
export const officeVisible = () => !!officeWin?.visible
export function hideOffice() {
  if (officeWin) { officeWin.visible = false; officeWin.keymode = Astal.Keymode.NONE }
  disarmClickaway()
}
export function toggleOffice(on?: Gdk.Monitor) { if (officeWin?.visible) hideOffice(); else showOffice(on) }

const askTip = (t: Card) => [t.title, "", t.ask?.question ?? "", ...(t.ask?.options ?? []).map((o, i) => `${i + 1}  ${o}`), "", "answered on arena's board: Alt+b"].join("\n")

export default function Office() {
  return (
    <window
      $={(self) => {
        officeWin = self
        self.add_controller(closeKeys({ close: hideOffice, q: true }))
      }}
      visible={false}
      cssClasses={["office"]}
      namespace="astal-shell-office"
      name="office"
      // like the hub: a sheet over the windows with a field beside it, so it stays up wherever
      // the pointer goes and the first click outside it closes it
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.NONE}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT}
      marginTop={36}
      marginLeft={48}
      application={app}
    >
      <box>
        <box cssClasses={["clickaway-field"]} hexpand vexpand $={(self) => clickawayField(self, hideOffice)} />
        <scrolledwindow cssClasses={["sheet", "right"]} hexpand={false} halign={Gtk.Align.END} hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC}>
          <Panel title={"\u{f06a9}  OFFICE"} cssClasses={["card", "card-office"]} spacing={6}>
            <label cssClasses={["dim"]} label="no Claude sessions" xalign={0} visible={shown((l) => l.length === 0)} />
            <box orientation={Gtk.Orientation.VERTICAL}>
              <For each={shown} id={(r: Row) => `${r.session.id} ${r.session.state} ${r.session.since} ${r.session.doing} ${r.ticket?.id} ${r.yours}`}>
                {(r: Row) => (
                  <button cssClasses={["office-row", r.session.state, ...(r.yours ? ["yours"] : [])]} onClicked={() => { hideOffice(); void goTo(r.session) }} tooltipText={r.session.said ?? r.session.cwd}>
                    <box orientation={Gtk.Orientation.VERTICAL}>
                      <label cssClasses={["head"]} label={readAt((t) => rowLines(r, t)[0])} xalign={0} ellipsize={3} maxWidthChars={ROW_CHARS} />
                      <label cssClasses={["dim", "sm"]} label={rowLines(r, 0)[1]} xalign={0} ellipsize={3} maxWidthChars={ROW_CHARS} />
                    </box>
                  </button>
                )}
              </For>
            </box>
            <RuleH />
            <label cssClasses={["board-line"]} label={board(boardLine)} xalign={0} />
            <box orientation={Gtk.Orientation.VERTICAL}>
              <For each={asks} id={(t: Card) => `${t.id} ${t.ask?.id}`}>
                {(t: Card) => (
                  <button cssClasses={["office-row", "ask"]} onClicked={() => { hideOffice(); goToArena() }} tooltipText={askTip(t)}>
                    <box orientation={Gtk.Orientation.VERTICAL}>
                      <label cssClasses={["head"]} label={`? #${t.id} ${t.repo}  asks you`} xalign={0} ellipsize={3} maxWidthChars={ROW_CHARS} />
                      <label cssClasses={["dim", "sm"]} label={t.ask?.question.replace(/\s+/g, " ") ?? ""} xalign={0} ellipsize={3} maxWidthChars={ROW_CHARS} />
                    </box>
                  </button>
                )}
              </For>
            </box>
            <label cssClasses={["dim", "sm"]} label="click a row: its Claude in arena · an ask: arena, the board is Alt+b · esc" xalign={0} wrap maxWidthChars={ROW_CHARS} />
          </Panel>
        </scrolledwindow>
      </box>
    </window>
  )
}
