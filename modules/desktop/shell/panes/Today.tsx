// TODAY: what needs me, one list — notices not yet dismissed, the agenda (khal), the agents
// awaiting an answer. Each row is a click: a notice dismisses, an agent line opens the roster.
import Gtk from "gi://Gtk?version=4.0"
import Notifd from "gi://AstalNotifd"
import { For, createBinding, createComputed } from "ags"
import { agenda } from "./Calendar"
import { agents } from "../lib/agents"
import { popAgents } from "../surfaces/Tray"
import { urgencyOf } from "../surfaces/Notifications"

type Row = { key: string; glyph: string; cls: string; text: string; sub?: string; onClick?: () => void }

const notifd = Notifd.get_default()

export function TodayCard() {
  const notices = createBinding(notifd, "notifications")((ns) => [...ns].sort((a, b) => b.time - a.time))
  const rows = createComputed([notices, agenda, agents], (ns, ag, a): Row[] => {
    const out: Row[] = []
    if (a.awaiting > 0)
      out.push({ key: "agents", glyph: "\u{f06a9}", cls: "pink", text: `${a.awaiting} ${a.awaiting === 1 ? "agent awaits" : "agents await"} you`, onClick: popAgents })
    for (const n of ns.slice(0, 6)) {
      const u = urgencyOf(n)
      out.push({
        key: `n${n.id}`, glyph: u === "critical" ? "\u{f0026}" : "\u{f009a}", cls: u === "critical" ? "red" : u === "low" ? "dim" : "amber",
        text: n.summary, sub: n.appName, onClick: () => n.dismiss(),
      })
    }
    if (ns.length > 6) out.push({ key: "more", glyph: "…", cls: "dim", text: `${ns.length - 6} more notices in the hub` })
    let day = ""
    for (const l of ag.lines.slice(0, 8)) {
      if (l.startsWith("·")) { day = l.replace(/^· /, ""); continue }
      out.push({ key: `a${day}${l}`, glyph: "\u{f00ed}", cls: "cyan", text: l, sub: day })
    }
    return out
  })
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={1} cssClasses={["today"]}>
      <For each={rows}>
        {(r) => (
          <button cssClasses={["row", "today-row"]} onClicked={() => r.onClick?.()} sensitive={!!r.onClick}>
            <box spacing={8}>
              <label cssClasses={[r.cls]} label={r.glyph} widthChars={2} />
              <label cssClasses={["sm"]} label={r.text} xalign={0} hexpand ellipsize={3} maxWidthChars={34} />
              <label cssClasses={["dim", "sm"]} label={r.sub ?? ""} xalign={1} visible={!!r.sub} />
            </box>
          </button>
        )}
      </For>
      <label cssClasses={["green"]} label="nothing needs you" visible={rows((r) => r.length === 0)} xalign={0} />
    </box>
  )
}
