// The launcher (retires anyrun) and the clipboard picker (retires the fuzzel stopgap): one
// list widget, two sources. A centred pane with a `>` prompt and a block cursor, results
// below, the selection in inverse video. Prefixes switch mode: apps by default, `=` calc, `>` verbs (mise tasks)
// (qalc), `/` files (fd from ~), `:` run a shell line. Up/Down or Ctrl+j/k, Enter, Escape.
import { parseSpec } from "../lib/timer"
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import { closeKeys } from "../lib/keys"
import { clickawayField } from "./Clickaway"
import GLib from "gi://GLib?version=2.0"
import Apps from "gi://AstalApps"
import Hyprland from "gi://AstalHyprland"
import { For, createState, createComputed } from "ags"
import { execAsync } from "ags/process"
import { Panel } from "../lib/tui"
import { remember, score, recent, times, type Memory } from "../lib/funes"

type Item = { icon?: string; glyph?: string; title: string; sub?: string; run: () => void | Promise<void>; key: string; mode?: Mode }
type Mode = "apps" | "calc" | "files" | "shell" | "clip" | "verbs"

const apps = new Apps.Apps()
const home = GLib.get_home_dir()
const REPO = `${home}/projects/ficciones`
/** A verb runs in its own ghostty window from the repo, and the window stays until you dismiss it. */
const runVerb = (name: string) =>
  execAsync(["ghostty", `--title=mise ${name}`, "-e", "sh", "-c", `cd ${REPO} && mise run ${name}; printf '\n[done — enter to close] '; read _`]).then(() => void 0)

let win: Astal.Window | null = null
let entry: Gtk.Entry | null = null
let modeOverride: Mode | null = null

const [query, setQuery] = createState("")
const [items, setItems] = createState<Item[]>([])
const [sel, setSel] = createState(0)
const mode = query((q): Mode =>
  modeOverride ?? (q.startsWith("=") ? "calc" : q.startsWith("/") ? "files" : q.startsWith(":") ? "shell" : q.startsWith(">") ? "verbs" : "apps"))

/** A remembered thing as an item again: apps relaunch, shell lines rerun, files reopen, sums recopy. */
function recall(m: Memory): Item | null {
  if (m.mode === "apps") {
    const a = apps.get_list().find((x) => x.entry === m.key)
    if (!a) return null
    return { icon: a.iconName || "application-x-executable", title: a.name, sub: `${times("apps", m.key)}×`, key: a.entry, mode: "apps", run: () => { a.launch() } }
  }
  if (m.mode === "shell") return { glyph: ":", title: m.key, sub: `${times("shell", m.key)}×`, key: m.key, mode: "shell", run: () => execAsync(["sh", "-c", m.key]).then(() => void 0) }
  if (m.mode === "files") return { glyph: "/", title: m.key.replace(home, "~"), sub: `${times("files", m.key)}×`, key: m.key, mode: "files", run: () => execAsync(["xdg-open", m.key]).then(() => void 0) }
  if (m.mode === "calc") return { glyph: "=", title: m.title, sub: m.key, key: m.key, mode: "calc", run: () => execAsync(["wl-copy", m.title]).then(() => void 0) }
  if (m.mode === "verbs") return { glyph: ">", title: m.key, sub: `${times("verbs", m.key)}×`, key: m.key, mode: "verbs", run: () => runVerb(m.key) }
  return null
}

let seq = 0
async function search(q: string) {
  const my = ++seq
  const m = mode.peek()
  const body = m === "apps" || m === "clip" ? q : q.slice(1).trim()
  let out: Item[] = []
  try {
    if (m === "apps") {
      // "25m", "14:30", "pomo", "stop": the deck's timer, first, ahead of any app match
      const tm = body ? parseSpec(body) : null
      if (!body) {
        // the empty prompt: what Funes remembers, across modes, then the apps by frecency
        const seen = new Set<string>()
        out = recent(8, ["apps", "shell", "files", "calc"]).map(recall).filter((x): x is Item => { if (!x) return false; seen.add(`${x.mode}:${x.key}`); return true })
        for (const a of [...apps.get_list()].sort((a, b) => score("apps", b.entry) - score("apps", a.entry)).slice(0, 12 - out.length)) {
          if (seen.has(`apps:${a.entry}`)) continue
          out.push({ icon: a.iconName || "application-x-executable", title: a.name, sub: a.description ?? "", key: a.entry, mode: "apps", run: () => { a.launch() } })
        }
      } else {
        // fuzzy order, then the remembered ones float: a launcher that learns
        const hits = apps.fuzzy_query(body).slice(0, 24)
        out = hits
          .map((a, i) => ({ a, s: score("apps", a.entry) * 10 - i }))
          .sort((x, y) => y.s - x.s)
          .slice(0, 12)
          .map(({ a }) => ({
            icon: a.iconName || "application-x-executable", title: a.name, sub: times("apps", a.entry) ? `${a.description ?? ""}  · ${times("apps", a.entry)}×` : (a.description ?? ""), key: a.entry, mode: "apps",
            run: () => { a.launch() },
          }))
        // a shell line typed before that starts the same way rides along
        for (const r of recent(3, ["shell"]).filter((r) => r.key.startsWith(body))) { const it = recall(r); if (it) out.push(it) }
        if (tm) out.unshift({ glyph: "\u{f051b}", title: tm.title, sub: "timer", key: `timer:${body}`, run: () => { tm.start() } })
      }
    } else if (m === "calc") {
      if (body) {
        const r = (await execAsync(["qalc", "-t", body])).trim()
        out = [{ glyph: "=", title: r, sub: body, key: body, mode: "calc", run: () => execAsync(["wl-copy", r]).then(() => void 0) }]
      }
    } else if (m === "files") {
      if (body.length >= 2) {
        const r = await execAsync(["fd", "--max-results", "14", "--hidden", "--exclude", ".git", "--exclude", "node_modules", "--exclude", ".cache", "-i", body, home])
        out = r.trim().split("\n").filter(Boolean).map((p) => ({
          glyph: "/", title: p.replace(home, "~"), key: p, mode: "files" as Mode, run: () => execAsync(["xdg-open", p]).then(() => void 0),
        })).sort((a, b) => score("files", b.key) - score("files", a.key))
      } else {
        out = recent(8, ["files"]).map(recall).filter((x): x is Item => !!x)
      }
    } else if (m === "shell") {
      out = body ? [{ glyph: ":", title: body, sub: "run in a shell", key: body, mode: "shell", run: () => execAsync(["sh", "-c", body]).then(() => void 0) }] : []
      // lines run before that start the same way, most-reached-for first
      for (const r of recent(8, ["shell"]).filter((r) => r.key !== body && r.key.startsWith(body))) { const it = recall(r); if (it) out.push(it) }
    } else if (m === "verbs") {
      // `>` — the machine's verbs (omarchy-menu's shape, steals doc O3): every mise task in the
      // repo, run in its own ghostty so its output is a window, not a lost stdout
      const r = await execAsync(["mise", "--cd", REPO, "tasks", "ls", "--json"])
      const tasks = JSON.parse(r) as { name: string; description?: string }[]
      const needle = body.toLowerCase()
      out = tasks
        .filter((t) => !needle || t.name.toLowerCase().includes(needle) || (t.description ?? "").toLowerCase().includes(needle))
        .sort((a, b) => score("verbs", b.name) - score("verbs", a.name) || a.name.localeCompare(b.name))
        .slice(0, 14)
        .map((t) => ({ glyph: ">", title: t.name, sub: (t.description ?? "").slice(0, 80), key: t.name, mode: "verbs" as Mode, run: () => runVerb(t.name) }))
    } else if (m === "clip") {
      const r = await execAsync(["cliphist", "list"])
      const rows = r.split("\n").filter(Boolean)
      const needle = body.toLowerCase()
      out = rows
        .map((l) => { const [id, ...rest] = l.split("\t"); return { id, text: rest.join("\t") } })
        .filter((e) => !needle || e.text.toLowerCase().includes(needle))
        .slice(0, 14)
        .map((e) => ({
          glyph: "\u{f0cea}", title: e.text.replace(/\s+/g, " ").slice(0, 70), key: e.id,
          run: () => execAsync(["sh", "-c", `cliphist list | grep -m1 '^${e.id}\\t' | cliphist decode | wl-copy`]).then(() => void 0),
        }))
    }
  } catch (e) {
    out = [{ glyph: "!", title: String(e).split("\n")[0].slice(0, 70), key: "err", run: () => {} }]
  }
  if (my !== seq) return
  setItems(out)
  setSel(0)
}

function activate() {
  const it = items.peek()[sel.peek()]
  if (!it) return
  hide()
  if (it.mode && it.key !== "err") remember({ key: it.key, mode: it.mode, title: it.title, sub: it.sub })
  Promise.resolve(it.run()).catch(console.error)
}
function hide() { if (win) win.visible = false }

export function showLauncher(m: Mode | null = null) {
  if (!win) return
  modeOverride = m
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((x) => x.connector === name)
  if (mon) win.gdkmonitor = mon
  win.visible = true
  if (entry) { entry.text = ""; entry.grab_focus() }
  setQuery("")
  search("")
}
export function toggleLauncher(m: Mode | null = null) { if (win?.visible) hide(); else showLauncher(m) }

const prompt: Record<Mode, string> = { apps: ">", calc: "=", files: "/", shell: ":", clip: "\u{f0cea}", verbs: "\u{f0493}" }
const hint: Record<Mode, string> = { apps: "apps · =calc · /files · :shell · >verbs", calc: "qalc · Enter copies", files: "fd from ~ · Enter opens", shell: "Enter runs", clip: "Enter copies", verbs: "mise tasks · Enter runs in a window" }

export default function Launcher() {
  const onKey = (kv: number, state: number) => {
    const ctrl = state & Gdk.ModifierType.CONTROL_MASK
    const n = items.peek().length
    if (kv === Gdk.KEY_Down || (ctrl && kv === Gdk.KEY_j) || kv === Gdk.KEY_Tab) return setSel((s) => (n ? (s + 1) % n : 0)), true
    if (kv === Gdk.KEY_Up || (ctrl && kv === Gdk.KEY_k) || kv === Gdk.KEY_ISO_Left_Tab) return setSel((s) => (n ? (s + n - 1) % n : 0)), true
    if (kv === Gdk.KEY_Return || kv === Gdk.KEY_KP_Enter) return activate(), true
    return false
  }
  return (
    <window
      $={(self) => {
        win = self
        self.add_controller(closeKeys({ close: hide, capture: true, onKey }))
      }}
      visible={false}
      cssClasses={["launcher"]}
      namespace="astal-shell-launcher"
      name="launcher"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.EXCLUSIVE}
      exclusivity={Astal.Exclusivity.IGNORE}
      // the whole monitor: a transparent field around the pane, and a click on it closes
      // (Andrew, 2026-09-07: "clickaway on anything that pops up")
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT}
      application={app}
    >
      <overlay>
        <box cssClasses={["clickaway-field"]} hexpand vexpand $={(self) => clickawayField(self, hide)} />
      <box $type="overlay" halign={Gtk.Align.CENTER} valign={Gtk.Align.START} marginTop={180}>
      <Panel title={mode((m) => (m === "clip" ? "CLIPBOARD" : "RUN"))} cssClasses={["launch-pane", "focused"]} spacing={4}>
        <box cssClasses={["prompt"]} spacing={8}>
          <label cssClasses={["ps"]} label={mode((m) => prompt[m])} />
          <entry
            $={(self) => (entry = self)}
            hexpand
            onNotifyText={(e) => { setQuery(e.text); search(e.text) }}
            placeholderText=""
          />
          <label cssClasses={["hint"]} label={mode((m) => hint[m])} />
        </box>
        <box orientation={Gtk.Orientation.VERTICAL} cssClasses={["results"]} spacing={1}>
          <For each={items}>
            {(it, i) => (
              <button
                cssClasses={createComputed(() => { const s = sel(), idx = i(); return ["result", ...(s === idx ? ["chip"] : [])] })}
                onClicked={() => { setSel(i.peek()); activate() }}
              >
                <box spacing={10}>
                  {it.icon ? <image iconName={it.icon} pixelSize={20} /> : <label cssClasses={["glyph"]} label={it.glyph ?? ""} widthChars={2} />}
                  <label label={it.title} xalign={0} ellipsize={3} maxWidthChars={60} />
                  <label cssClasses={["sub"]} label={it.sub ?? ""} xalign={1} hexpand ellipsize={3} maxWidthChars={36} visible={!!it.sub} />
                </box>
              </button>
            )}
          </For>
          <label cssClasses={["dim", "sm"]} label="nothing" visible={createComputed(() => { const l = items(), q = query(); return l.length === 0 && q.length > 0 })} xalign={0} />
        </box>
      </Panel>
      </box>
      </overlay>
    </window>
  )
}
