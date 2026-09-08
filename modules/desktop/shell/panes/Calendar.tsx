// The month, today chipped. The date line above it is the card's headline.
import Gtk from "gi://Gtk?version=4.0"
import GLib from "gi://GLib?version=2.0"
import { createPoll } from "ags/time"
import { execAsync } from "ags/process"
import { For, With, createState } from "ags"
import { RuleH } from "../lib/tui"

/**
 * The agenda: khal over vdirsyncer's local mirror of every CalDAV account (work, home), the
 * next three days. Until those are set up the card says so — the shell never talks CalDAV
 * itself. Polled every 5 minutes.
 */
export const agenda = createPoll<{ ok: boolean; lines: string[] }>({ ok: false, lines: [] }, 5 * 60_000, async () => {
  try {
    const out = await execAsync(["khal", "list", "--format", "{start-time} {title}", "--day-format", "· {name} {date}", "now", "3d"])
    return { ok: true, lines: out.trim().split("\n").filter(Boolean).slice(0, 12) }
  } catch {
    return { ok: false, lines: [] }
  }
})

function Agenda() {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={1} cssClasses={["agenda"]}>
      <For each={agenda((a) => a.lines)}>
        {(l: string) => <label cssClasses={l.startsWith("·") ? ["k", "sm", "agenda-day"] : ["sm"]} label={l.replace(/^· /, "")} xalign={0} ellipsize={3} maxWidthChars={44} />}
      </For>
      <label cssClasses={["dim", "sm"]} label="no calendars yet — vdirsyncer + khal" xalign={0} visible={agenda((a) => !a.ok)} />
      <label cssClasses={["dim", "sm"]} label="nothing in the next three days" xalign={0} visible={agenda((a) => a.ok && a.lines.length === 0)} />
    </box>
  )
}

/** A month as six rows of seven, Sunday first (Andrew, 2026-09-08); null pads the edges. */
function monthRows(year: number, month: number): (number | null)[][] {
  const first = GLib.DateTime.new_local(year, month, 1, 0, 0, 0)!
  const lead = first.get_day_of_week() % 7 // GLib: Mon=1 … Sun=7 → Sunday = 0
  const days = first.add_months(1)!.add_days(-1)!.get_day_of_month()
  const cells: (number | null)[] = [...Array(lead).fill(null), ...Array.from({ length: days }, (_, i) => i + 1)]
  // always six rows: the grid keeps one height across months, so the agenda under it never
  // jumps (Andrew, 2026-09-08)
  while (cells.length < 42) cells.push(null)
  const rows: (number | null)[][] = []
  for (let i = 0; i < cells.length; i += 7) rows.push(cells.slice(i, i + 7))
  return rows
}

export function CalendarCard() {
  const now = GLib.DateTime.new_now_local()
  // the month on show; ‹ › walk it, the title snaps back to today
  const [view, setView] = createState({ year: now.get_year(), month: now.get_month() })
  const step = (n: number) => {
    const v = view.get()
    const d = GLib.DateTime.new_local(v.year, v.month, 1, 0, 0, 0)!.add_months(n)!
    setView({ year: d.get_year(), month: d.get_month() })
  }
  const home = () => { const t = GLib.DateTime.new_now_local(); setView({ year: t.get_year(), month: t.get_month() }) }
  const clock = createPoll("", 1000, () => GLib.DateTime.new_now_local().format("%A %d %B · %H:%M:%S")!)
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <label cssClasses={["headline-lg"]} label={clock} xalign={0} />
      <box cssClasses={["cal-nav"]} spacing={4}>
        <button cssClasses={["act"]} onClicked={() => step(-1)} tooltipText="previous month"><label label={"\u{f0141}"} /></button>
        <button cssClasses={["cal-title"]} hexpand onClicked={home} tooltipText="back to this month">
          <label label={view((v) => GLib.DateTime.new_local(v.year, v.month, 1, 0, 0, 0)!.format("%B %Y")!)} />
        </button>
        <button cssClasses={["act"]} onClicked={() => step(1)} tooltipText="next month"><label label={"\u{f0142}"} /></button>
      </box>
      <box cssClasses={["cal-head"]} homogeneous hexpand>
        {["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"].map((d) => <label label={d} hexpand />)}
      </box>
      <With value={view}>
        {(v) => {
          const t = GLib.DateTime.new_now_local()
          const today = v.year === t.get_year() && v.month === t.get_month() ? t.get_day_of_month() : -1
          return (
            <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
              {monthRows(v.year, v.month).map((r) => (
                <box homogeneous hexpand>
                  {r.map((d) => (
                    <label
                      cssClasses={["cal-day", ...(d === today ? ["chip"] : []), ...(d === null ? ["dim"] : [])]}
                      label={d === null ? "" : String(d)}
                      hexpand
                    />
                  ))}
                </box>
              ))}
            </box>
          )
        }}
      </With>
      <RuleH />
      <Agenda />
    </box>
  )
}
