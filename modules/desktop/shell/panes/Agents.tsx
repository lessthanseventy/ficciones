// AGENTS: thread counts, then every open thread as a row — its agent and warmth when staffed,
// who it awaits — and, under them, the selected thread's brief: goal, lead, next, blockers,
// the last messages (Andrew, 2026-09-07: "agents → dossier"). j/k, Enter, click.
import Gtk from "gi://Gtk?version=4.0"
import { For, createComputed, createState, type Accessor } from "ags"
import { agents, dossier, type Dossier, type Thread } from "../lib/agents"
import { cursorOf, select } from "../lib/nav"
import { RuleH } from "../lib/tui"
import { hhmm } from "../lib/format"

export const roster = agents((a) => a.roster)
export const threads = agents((a) => a.threads)

const [brief, setBrief] = createState<Dossier | null>(null)
let loading = 0
/** load the brief of the thread under the cursor (called on select) */
export async function loadBrief(i: number) {
  const t = threads.peek()[i]
  if (!t) { setBrief(null); return }
  const my = ++loading
  const d = await dossier(t.id)
  if (my === loading) setBrief(d)
}
// the cursor's row is the brief shown: any move re-fetches (cheap: one rpc)
cursorOf("AGENTS").subscribe(() => { loadBrief(cursorOf("AGENTS").peek()) })

const line = (x: { text?: string; title?: string }) => x.text ?? x.title ?? ""

export function AgentsCard() {
  const cur = cursorOf("AGENTS")
  const staffed = (t: Thread) => roster.peek().find((r) => r.thread_id === t.id)
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={6}>
      <box spacing={14} cssClasses={["counts"]}>
        <box spacing={6}><label cssClasses={["k"]} label="open" /><label cssClasses={["amber"]} label={agents((a) => String(a.counts.open ?? 0))} /></box>
        <box spacing={6}><label cssClasses={["k"]} label="done" /><label cssClasses={["st-done"]} label={agents((a) => String(a.counts.closed ?? a.counts.done ?? 0))} /></box>
        <box spacing={6}><label cssClasses={["k"]} label="awaiting you" /><label cssClasses={agents((a) => (a.awaiting > 0 ? ["pink"] : ["dim"]))} label={agents((a) => String(a.awaiting))} /></box>
      </box>
      <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC} propagateNaturalHeight maxContentHeight={190}>
      <box orientation={Gtk.Orientation.VERTICAL}>
      <For each={threads}>
        {(t, i) => {
          const r = staffed(t)
          return (
            <button cssClasses={createComputed(() => { const c = cur(), idx = i(); return ["row", "thread-row", ...(c === idx ? ["chip"] : [])] })} onClicked={() => select("AGENTS", i.peek())}>
              <box spacing={8}>
                <label cssClasses={[r ? (r.warm ? "st-working" : "st-idle") : "dim"]} label={r ? (r.warm ? "●" : "○") : "·"} />
                <label cssClasses={["dim", "sm"]} label={`#${t.id}`} widthChars={3} xalign={1} />
                <label label={t.title} hexpand xalign={0} ellipsize={3} maxWidthChars={22} />
                <label cssClasses={["pink", "sm"]} label={r ? r.agent : ""} visible={!!r} />
                <label cssClasses={["cyan", "sm"]} label={t.stage ?? ""} visible={!!t.stage} />
                <label cssClasses={["pink", "sm"]} label={t.awaiting ? `\u{f0e7e} ${t.awaiting}` : t.prompt ? `\u{f0e7e} ${t.prompt.summary}` : ""} visible={!!t.awaiting || !!t.prompt} ellipsize={3} maxWidthChars={24} />
              </box>
            </button>
          )
        }}
      </For>
      </box>
      </scrolledwindow>
      <label cssClasses={agents((a) => (a.ok ? ["dim"] : ["red"]))} label={agents((a) => (a.ok ? "no open threads" : a.note ?? ""))} visible={agents((a) => !a.ok || a.threads.length === 0)} xalign={0} />
      <RuleH />
      {/* the brief of the thread under the cursor */}
      <Brief brief={brief} />
    </box>
  )
}

/** A thread's brief: goal, lead, next, blockers, the last three messages. */
export function Brief({ brief }: { brief: Accessor<Dossier | null> }) {
  return (
    <box orientation={Gtk.Orientation.VERTICAL} spacing={3} cssClasses={["brief"]} visible={brief((b) => !!b)}>
      <box spacing={8}>
        <label cssClasses={["k", "sm"]} label="goal" widthChars={5} xalign={0} />
        <label cssClasses={["amber"]} label={brief((b) => b?.goal ?? "—")} xalign={0} hexpand wrap maxWidthChars={40} />
      </box>
      <box spacing={8}>
        <label cssClasses={["k", "sm"]} label="lead" widthChars={5} xalign={0} />
        <label cssClasses={["pink"]} label={brief((b) => b?.lead ?? "—")} xalign={0} hexpand />
      </box>
      <box spacing={8} visible={brief((b) => !!b?.next)}>
        <label cssClasses={["k", "sm"]} label="next" widthChars={5} xalign={0} />
        <label label={brief((b) => b?.next ?? "")} xalign={0} hexpand wrap maxWidthChars={40} />
      </box>
      <box spacing={8} visible={brief((b) => (b?.blockers?.shown?.length ?? 0) > 0)}>
        <label cssClasses={["red", "sm"]} label="block" widthChars={5} xalign={0} />
        <label cssClasses={["red"]} label={brief((b) => (b?.blockers?.shown ?? []).map(line).join(" · "))} xalign={0} hexpand wrap maxWidthChars={40} />
      </box>
      <For each={brief((b): Dossier["recent"] => (b?.recent ?? []).slice(-3))}>
        {(m: Dossier["recent"][number]) => (
          <box spacing={8} cssClasses={["msg"]}>
            <label cssClasses={["dim", "sm"]} label={hhmm(m.at)} />
            <label cssClasses={["cyan", "sm"]} label={m.author} widthChars={8} xalign={0} ellipsize={3} />
            {/* one line per message: a body's own newlines would stack it into a tall block */}
            <label cssClasses={["sm"]} label={m.body.replace(/\s+/g, " ").trim()} tooltipText={m.body} xalign={0} hexpand ellipsize={3} maxWidthChars={40} />
          </box>
        )}
      </For>
    </box>
  )
}
