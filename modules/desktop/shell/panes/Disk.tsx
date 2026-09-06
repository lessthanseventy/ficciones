// DISK: one meter per mount, red past 90 %, the fs type dim on the right.
import Gtk from "gi://Gtk?version=4.0"
import { For } from "ags"
import { mounts, gb } from "../lib/disk"
import { meter } from "../lib/format"

export function DiskCard() {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={3}>
      <For each={mounts}>
        {(m) => (
          <box spacing={10} cssClasses={["mount", m.frac > 0.9 ? "hot" : m.frac > 0.7 ? "busy" : "idle"]}>
            <label cssClasses={["cyan", "sm"]} label={m.target} widthChars={16} xalign={0} ellipsize={1} />
            <label cssClasses={["bar", "sm"]} label={meter(m.frac, 16)} />
            <label cssClasses={["num", "sm"]} label={`${Math.round(m.frac * 100)}%`} widthChars={4} xalign={1} />
            <label cssClasses={["dim", "sm"]} label={`${gb(m.used)} of ${gb(m.size)}`} widthChars={13} xalign={1} />
            <label cssClasses={["faint", "sm"]} label={m.fstype} widthChars={6} xalign={1} />
          </box>
        )}
      </For>
      <label cssClasses={["dim", "sm"]} label="df said nothing" visible={mounts((m) => m.length === 0)} xalign={0} />
    </box>
  )
}
