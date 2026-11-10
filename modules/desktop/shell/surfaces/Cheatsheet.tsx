// The keybind cheatsheet: the binds as scripts/manual-gen.sh reads them out of hyprland.lua
// (assets/keys.json, the manual's keys page as data, each bind already in words). `hyprctl binds
// -j` knows a Lua bind only as a handle, so the source is the record. Columns of `MOD+KEY  what`; type to filter,
// Esc closes. Super+? or `astal-shell toggle cheatsheet`.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Hyprland from "gi://AstalHyprland"
import { createState, createComputed, For } from "ags"
import { readFileAsync } from "ags/file"
import { Panel } from "../lib/tui"
import { closeKeys } from "../lib/keys"
import { clickawayField } from "./Clickaway"

type Key = { group: string; keys: string; does: string }
type Group = { title: string; rows: Key[] }


const keyName = (k: string) => k.replace(/SUPER/g, "Super").replace(/SHIFT/g, "Shift").replace(/CTRL/g, "Ctrl").replace(/ALT/g, "Alt").replace(/XF86Audio/, "").replace(/XF86MonBrightness/, "Brightness")

let win: Astal.Window | null = null
let entry: Gtk.Entry | null = null
const [all, setAll] = createState<Key[]>([])
const [q, setQ] = createState("")
const PER_ROW = 3

const src = () => (typeof SRC === "string" ? SRC : ".")
async function load() {
  try {
    const keys: Key[] = JSON.parse(await readFileAsync(`${src()}/assets/keys.json`))
    setAll(keys.map((k) => ({ group: k.group, keys: keyName(k.keys), does: k.does })))
  } catch (e) {
    setAll([{ group: "keys", keys: "!", does: String(e).slice(0, 80) }])
  }
}

const shown = createComputed(() => {
  const needle = q().trim().toLowerCase()
  const groups: Group[] = []
  for (const k of all()) {
    if (needle && !`${k.keys} ${k.does} ${k.group}`.toLowerCase().includes(needle)) continue
    const g = groups.find((x) => x.title === k.group)
    if (g) g.rows.push(k)
    else groups.push({ title: k.group, rows: [k] })
  }
  const chunked: Group[][] = []
  for (let i = 0; i < groups.length; i += PER_ROW) chunked.push(groups.slice(i, i + PER_ROW))
  return chunked
})

export function toggleCheatsheet() {
  if (!win) return
  if (win.visible) return void (win.visible = false)
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((m) => m.connector === name)
  if (mon) win.gdkmonitor = mon
  load().then(() => {
    if (!win) return
    win.visible = true
    if (entry) { entry.text = ""; entry.grab_focus() }
  })
}

export default function Cheatsheet() {
  return (
    <window
      $={(self) => {
        win = self
        // capture: Esc closes from inside the filter too
        self.add_controller(closeKeys({ close: () => (self.visible = false), capture: true }))
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
      <Panel title="KEYS · hyprland.lua" cssClasses={["sheet-pane", "focused"]}>
        <box orientation={Gtk.Orientation.VERTICAL} spacing={12}>
          <box spacing={8}>
            <entry $={(self) => (entry = self)} hexpand onNotifyText={(e) => setQ(e.text)} placeholderText="type to filter" />
            <label cssClasses={["hint"]} label="Esc closes" />
          </box>
          <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} propagateNaturalHeight propagateNaturalWidth maxContentHeight={820}>
            <box orientation={Gtk.Orientation.VERTICAL} spacing={12}>
              <For each={shown}>
                {(row) => (
                  <box spacing={20} cssClasses={["columns"]} homogeneous>
                    {row.map((g) => (
                      <box orientation={Gtk.Orientation.VERTICAL} spacing={1} cssClasses={["col"]} valign={Gtk.Align.START}>
                        <label cssClasses={["k"]} label={g.title} xalign={0} />
                        {g.rows.map((r) => (
                          <box spacing={8}>
                            <label cssClasses={["keys"]} label={r.keys} xalign={1} widthChars={22} />
                            <label cssClasses={["what"]} label={r.does} xalign={0} ellipsize={3} maxWidthChars={34} tooltipText={r.does} />
                          </box>
                        ))}
                      </box>
                    ))}
                  </box>
                )}
              </For>
              <label cssClasses={["dim"]} label="no bind matches" visible={shown((s) => s.length === 0)} xalign={0} />
            </box>
          </scrolledwindow>
        </box>
      </Panel>
    </window>
  )
}
