// The keybind cheatsheet: `hyprctl binds -j`, live, so it cannot drift from the config.
// Grouped by dispatcher family into columns of `MOD+KEY  what`. Super+? or `astal-shell
// toggle cheatsheet`; any key closes.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { createState, For } from "ags"
import { execAsync } from "ags/process"
import { Panel } from "../lib/tui"
import { closeKeys } from "../lib/keys"
import { clickawayField } from "./Clickaway"

type Bind = { modmask: number; key: string; dispatcher: string; arg: string; description: string; submap: string; mouse: boolean }
type Row = { keys: string; what: string }
type Group = { title: string; rows: Row[] }

const MODS: [number, string][] = [[64, "Super"], [8, "Alt"], [4, "Ctrl"], [1, "Shift"]]
const mods = (m: number) => MODS.filter(([b]) => m & b).map(([, n]) => n).join("+")
const keyName = (k: string) => k.replace(/^mouse:272$/, "LMB").replace(/^mouse:273$/, "RMB").replace(/^XF86Audio/, "").replace(/^XF86MonBrightness/, "Brightness").replace(/^code:/, "#")

/** The shell's own verbs, in words. */
const SHELL_WORDS: Record<string, string> = {
  "toggle launcher": "launcher", "toggle clipboard": "clipboard", "toggle cheatsheet": "this sheet",
  "toggle drawer": "calendar", "toggle hub": "notifications", "toggle deck": "deck: log · media · agents · timer", "toggle dashboard": "dashboard", "toggle settings": "settings",
  "toggle weather": "weather", "show drawer agents": "agents", "show drawer calendar": "calendar",
  "backdrop": "backdrop: next mode", "theme": "light / dark", "crt": "crt scanlines", "glass": "glass",
  "sidecar toggle": "pin as sidecar", "colresize narrower": "column narrower", "colresize wider": "column wider",
}

/** A readable line for a dispatcher + arg; the description wins when the config sets one. */
function what(b: Bind): string {
  if (b.description) return b.description
  const a = b.arg.trim()
  switch (b.dispatcher) {
    case "exec": {
      const m = a.match(/^astal-shell\s+(.*)$/)
      if (m) return SHELL_WORDS[m[1].trim()] ?? `shell: ${m[1]}`.slice(0, 34)
      return a.replace(/^bash -c ['"]?/, "").slice(0, 34)
    }
    case "workspace": return `workspace ${a}`
    case "movetoworkspace": case "movetoworkspacesilent": return `move to ws ${a}`
    case "movefocus": return `focus ${a}`
    case "movewindow": return `move window ${a}`
    case "killactive": return "close window"
    case "togglefloating": return "float"
    case "fullscreen": return a === "1" ? "maximise" : "fullscreen"
    case "exit": return "exit hyprland"
    default: return `${b.dispatcher} ${a}`.trim().slice(0, 34)
  }
}

function group(b: Bind): string {
  if (b.mouse) return "mouse"
  if (b.dispatcher === "exec" && /sidecar|colresize/.test(b.arg)) return "move & size"
  if (b.dispatcher === "exec") return "launch"
  if (/workspace/.test(b.dispatcher)) return "workspaces"
  if (/focus|cycle/.test(b.dispatcher)) return "focus"
  if (/move|swap|resize|split|layoutmsg|scroller/.test(b.dispatcher)) return "move & size"
  if (/float|fullscreen|pin|kill|toggle|pseudo|special|group/.test(b.dispatcher)) return "window"
  return "other"
}
const ORDER = ["launch", "focus", "move & size", "workspaces", "window", "mouse", "other"]

let win: Astal.Window | null = null
const [rows, setRows] = createState<Group[][]>([])
const PER_ROW = 4

async function load() {
  try {
    const binds: Bind[] = JSON.parse(await execAsync(["hyprctl", "binds", "-j"]))
    const by = new Map<string, Row[]>()
    for (const b of binds) {
      if (b.submap) continue
      const keys = [mods(b.modmask), keyName(b.key)].filter(Boolean).join("+")
      const g = group(b)
      by.set(g, [...(by.get(g) ?? []), { keys, what: what(b) }])
    }
    const groups = ORDER.filter((g) => by.has(g)).map((g) => ({ title: g, rows: by.get(g)! }))
    const chunked: Group[][] = []
    for (let i = 0; i < groups.length; i += PER_ROW) chunked.push(groups.slice(i, i + PER_ROW))
    setRows(chunked)
  } catch (e) {
    setRows([[{ title: "binds", rows: [{ keys: "!", what: String(e).slice(0, 60) }] }]])
  }
}

export function toggleCheatsheet() {
  if (!win) return
  if (win.visible) return void (win.visible = false)
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (mon) win.gdkmonitor = mon
  load().then(() => { if (win) win.visible = true })
}

export default function Cheatsheet() {
  return (
    <window
      $={(self) => {
        win = self
        self.add_controller(closeKeys({ close: () => (self.visible = false), any: true }))
        clickawayField(self, () => (self.visible = false))
      }}
      visible={false}
      cssClasses={["cheatsheet"]}
      namespace="astal-shell-cheatsheet"
      name="cheatsheet"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.EXCLUSIVE}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP}
      marginTop={80}
      application={app}
    >
      <Panel title="KEYS · hyprctl binds" cssClasses={["sheet-pane", "focused"]}>
        <box orientation={Gtk.Orientation.VERTICAL} spacing={12}>
          <For each={rows}>
            {(row) => (
              <box spacing={20} cssClasses={["columns"]} homogeneous>
                {row.map((g) => (
                  <box orientation={Gtk.Orientation.VERTICAL} spacing={1} cssClasses={["col"]}>
                    <label cssClasses={["k"]} label={g.title} xalign={0} />
                    {g.rows.slice(0, 20).map((r) => (
                      <box spacing={8}>
                        <label cssClasses={["keys"]} label={r.keys} xalign={1} widthChars={17} ellipsize={1} />
                        <label cssClasses={["what"]} label={r.what} xalign={0} ellipsize={3} maxWidthChars={28} />
                      </box>
                    ))}
                    <label cssClasses={["dim", "sm"]} label={`+${g.rows.length - 20} more`} visible={g.rows.length > 20} xalign={0} />
                  </box>
                ))}
              </box>
            )}
          </For>
        </box>
      </Panel>
    </window>
  )
}
