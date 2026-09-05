// AGENTS: the Tlön roster — the pane no other shell can draw. Degrades to "channel down".
import Gtk from "gi://Gtk?version=4.0"
import { For } from "ags"
import { Panel } from "../lib/tui"
import { agents } from "../lib/agents"

export default function Agents() {
  const roster = agents((a) => a.roster)
  const counts = agents((a) =>
    a.ok ? Object.entries(a.counts).map(([k, v]) => `${k} ${v}`).join("   ") + `   awaiting ${a.awaiting}` : a.note ?? "",
  )
  return (
    <box orientation={Gtk.Orientation.VERTICAL}>
      <Panel title="THREADS"><label label={counts} xalign={0} cssClasses={agents((a) => (a.ok ? [] : ["dim"]))} /></Panel>
      <Panel title="ON THE CLOCK" spacing={2}>
        <For each={roster}>
          {(r) => (
            <box cssClasses={["row"]} spacing={12}>
              <label cssClasses={[r.warm ? "st-working" : "st-idle"]} label={r.warm ? "●" : "○"} />
              <label cssClasses={["pink"]} label={r.agent} widthChars={14} xalign={0} />
              <label cssClasses={["dim"]} label={`#${r.thread_id}`} widthChars={5} xalign={1} />
              <label label={r.title} xalign={0} hexpand />
            </box>
          )}
        </For>
        <label cssClasses={["dim"]} label="no one on the clock" visible={roster((r) => r.length === 0)} xalign={0} />
      </Panel>
    </box>
  )
}
