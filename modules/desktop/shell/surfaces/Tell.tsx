// Tell the orchestrator: a one-line entry at the top of the screen (Super+U). Enter runs
// `babylon tell "<line>"` and closes; a refusal stays open with babylon's reason; Esc sends nothing.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"
import Gio from "gi://Gio?version=2.0"
import Hyprland from "gi://AstalHyprland"
import { createState } from "ags"
import { closeKeys } from "../lib/keys"
import { clickawayField } from "./Clickaway"
import { Panel } from "../lib/tui"
import { noteTold } from "../lib/orchestrator"
import { sendTell, type Run } from "../lib/tell-core"

let win: Astal.Window | null = null
let entry: Gtk.Entry | null = null
const [refusal, setRefusal] = createState("")
let sending = false

const run: Run = (argv) =>
  new Promise((resolve, reject) => {
    try {
      const p = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDERR_PIPE)
      p.communicate_utf8_async(null, null, (_, r) => {
        try { const [, , err] = p.communicate_utf8_finish(r); resolve({ code: p.get_exit_status(), err: err ?? "" }) } catch (e) { reject(e) }
      })
    } catch (e) { reject(e) }
  })

function hide() { if (win) win.visible = false }

async function send() {
  const line = entry?.text.trim() ?? ""
  if (!line || sending) return
  sending = true
  const at = Math.floor(Date.now() / 1000)
  const sent = await sendTell(line, run)
  sending = false
  if (!sent.ok) return setRefusal(sent.reason)
  noteTold(at)
  hide()
}

export function showTell() {
  if (!win) return
  const name = Hyprland.get_default().focusedMonitor?.name
  const mon = app.get_monitors().find((x) => x.connector === name)
  if (mon) win.gdkmonitor = mon
  setRefusal("")
  win.visible = true
  if (entry) { entry.text = ""; entry.grab_focus() }
}
export function toggleTell() { if (win?.visible) hide(); else showTell() }

export default function Tell() {
  const onKey = (kv: number) => {
    if (kv !== Gdk.KEY_Return && kv !== Gdk.KEY_KP_Enter) return false
    void send()
    return true
  }
  return (
    <window
      $={(self) => {
        win = self
        self.add_controller(closeKeys({ close: hide, capture: true, onKey }))
      }}
      visible={false}
      cssClasses={["launcher", "tell"]}
      namespace="astal-shell-tell"
      name="tell"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.EXCLUSIVE}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT}
      application={app}
    >
      <overlay>
        <box cssClasses={["clickaway-field"]} hexpand vexpand $={(self) => clickawayField(self, hide)} />
        <box $type="overlay" halign={Gtk.Align.CENTER} valign={Gtk.Align.START} marginTop={60}>
          <Panel title="TELL" cssClasses={["launch-pane", "focused"]} spacing={4}>
            <box cssClasses={["prompt"]} spacing={8}>
              <label cssClasses={["ps"]} label="tell the orchestrator ❯" />
              <entry $={(self) => (entry = self)} hexpand onNotifyText={() => setRefusal("")} placeholderText="" />
              <label cssClasses={["hint"]} label="Enter sends · Esc closes" />
            </box>
            <label cssClasses={["refusal"]} label={refusal} xalign={0} wrap visible={refusal((r) => r.length > 0)} />
          </Panel>
        </box>
      </overlay>
    </window>
  )
}
