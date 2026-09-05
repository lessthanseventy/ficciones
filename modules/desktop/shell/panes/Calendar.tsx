// The month, today chipped. The date line above it is the card's headline.
import Gtk from "gi://Gtk?version=4.0"
import GLib from "gi://GLib?version=2.0"
import { createPoll } from "ags/time"

export function CalendarCard() {
  const now = GLib.DateTime.new_now_local()
  const first = GLib.DateTime.new_local(now.get_year(), now.get_month(), 1, 0, 0, 0)!
  const lead = (first.get_day_of_week() + 6) % 7 // Monday = 0
  const days = first.add_months(1)!.add_days(-1)!.get_day_of_month()
  const today = now.get_day_of_month()
  const cells: (number | null)[] = [...Array(lead).fill(null), ...Array.from({ length: days }, (_, i) => i + 1)]
  while (cells.length % 7) cells.push(null)
  const rows: (number | null)[][] = []
  for (let i = 0; i < cells.length; i += 7) rows.push(cells.slice(i, i + 7))
  const clock = createPoll("", 1000, () => GLib.DateTime.new_now_local().format("%A %d %B · %H:%M:%S")!)
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <label cssClasses={["headline-lg"]} label={clock} xalign={0} />
      <box cssClasses={["cal-head"]} homogeneous>
        {["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"].map((d) => <label label={d} />)}
      </box>
      {rows.map((r) => (
        <box homogeneous>
          {r.map((d) => (
            <label
              cssClasses={["cal-day", ...(d === today ? ["chip"] : []), ...(d === null ? ["dim"] : [])]}
              label={d === null ? "" : String(d)}
            />
          ))}
        </box>
      ))}
    </box>
  )
}
