// TODAY: what needs me, one list — notices not yet dismissed, the agenda (khal), the agents
// awaiting an answer. Each row is a click: a notice dismisses, an agent line opens the roster.
import Gtk from "gi://Gtk?version=4.0"
import { For, createComputed } from "ags"
import { agenda } from "./Calendar"
import { agents } from "../lib/agents"
import { popAgents } from "../surfaces/Deck"
import { urgencyOf, groups, dismissGroup } from "../surfaces/Notifications"

type Row = { key: string; glyph: string; cls: string; text: string; sub?: string; onClick?: () => void }

export function TodayCard() {
  const rows = createComputed((): Row[] => {
    const ns = groups(), ag = agenda(), a = agents()
    const out: Row[] = []
    if (a.awaiting > 0)
      out.push({ key: "agents", glyph: "\u{f06a9}", cls: "pink", text: `${a.awaiting} ${a.awaiting === 1 ? "agent awaits" : "agents await"} you`, onClick: popAgents })
    for (const g of ns.slice(0, 40)) {
      const n = g.head
      const u = urgencyOf(n)
      out.push({
        key: g.key, glyph: u === "critical" ? "\u{f0026}" : "\u{f009a}", cls: u === "critical" ? "red" : u === "low" ? "dim" : "amber",
        text: g.count > 1 ? `${n.summary}  ×${g.count}` : n.summary, sub: n.appName, onClick: () => dismissGroup(g),
      })
    }
    if (ns.length > 40) out.push({ key: "more", glyph: "…", cls: "dim", text: `${ns.length - 40} more notices in the hub` })
    let day = ""
    for (const l of ag.lines.slice(0, 40)) {
      if (l.startsWith("·")) { day = l.replace(/^· /, ""); continue }
      out.push({ key: `a${day}${l}`, glyph: "\u{f00ed}", cls: "cyan", text: l, sub: day })
    }
    return out
  })
  return (
    // scrolls: the card takes the row's height on the board and the list can be long
    <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} vexpand propagateNaturalHeight>
    <box orientation={Gtk.Orientation.VERTICAL} spacing={1} cssClasses={["today"]}>
      <For each={rows} id={(r) => r.key}>
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
    </scrolledwindow>
  )
}
