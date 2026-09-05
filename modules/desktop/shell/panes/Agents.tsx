// AGENTS: thread counts, then the roster as rows (j/k, click) — the pane no other shell draws.
import Gtk from "gi://Gtk?version=4.0"
import { For, createComputed } from "ags"
import { agents } from "../lib/agents"
import { cursorOf, select } from "../lib/nav"

export const roster = agents((a) => a.roster)

export function AgentsCard() {
  const cur = cursorOf("AGENTS")
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <box spacing={14} cssClasses={["counts"]}>
        <box spacing={6}><label cssClasses={["k"]} label="open" /><label cssClasses={["amber"]} label={agents((a) => String(a.counts.open ?? 0))} /></box>
        <box spacing={6}><label cssClasses={["k"]} label="done" /><label cssClasses={["st-done"]} label={agents((a) => String(a.counts.closed ?? a.counts.done ?? 0))} /></box>
        <box spacing={6}><label cssClasses={["k"]} label="awaiting you" /><label cssClasses={agents((a) => (a.awaiting > 0 ? ["pink"] : ["dim"]))} label={agents((a) => String(a.awaiting))} /></box>
      </box>
      <For each={roster}>
        {(r, i) => (
          <button cssClasses={createComputed([cur, i], (c, idx) => ["row", ...(c === idx ? ["chip"] : [])])} onClicked={() => select("AGENTS", i.get())}>
            <box spacing={8}>
              <label cssClasses={[r.warm ? "st-working" : "st-idle"]} label={r.warm ? "●" : "○"} />
              <label cssClasses={["pink"]} label={r.agent} widthChars={12} xalign={0} />
              <label cssClasses={["dim"]} label={`#${r.thread_id}`} />
              <label label={r.title} hexpand xalign={0} ellipsize={3} maxWidthChars={18} />
            </box>
          </button>
        )}
      </For>
      <label cssClasses={agents((a) => (a.ok ? ["dim"] : ["red"]))} label={agents((a) => (a.ok ? "no one on the clock" : a.note ?? ""))} visible={agents((a) => !a.ok || a.roster.length === 0)} xalign={0} />
    </box>
  )
}
