// JOURNAL: warnings amber, errors red, the unit cyan. Newest first.
import Gtk from "gi://Gtk?version=4.0"
import { For } from "ags"
import { journal, type Entry } from "../lib/journal"

export function JournalCard() {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={1} cssClasses={["journal"]}>
      <For each={journal((j) => j.lines)}>
        {(e: Entry) => (
          <box spacing={8} tooltipText={e.msg}>
            <label cssClasses={["faint", "sm"]} label={e.t} />
            <label cssClasses={["cyan", "sm"]} label={e.unit} widthChars={14} xalign={0} ellipsize={3} />
            <label cssClasses={[e.prio <= 3 ? "red" : "amber", "sm"]} label={e.msg} xalign={0} hexpand ellipsize={3} maxWidthChars={60} />
          </box>
        )}
      </For>
      <label cssClasses={["green"]} label="quiet journal" visible={journal((j) => j.ok && j.lines.length === 0)} xalign={0} />
      <label cssClasses={["red"]} label="journal unreadable" visible={journal((j) => !j.ok)} xalign={0} />
    </box>
  )
}
