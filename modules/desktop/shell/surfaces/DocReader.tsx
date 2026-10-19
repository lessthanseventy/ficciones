// A coworker's doc (a spec, a plan) read in place: an alert's Read it opens it as a sheet over the
// desktop, rendered from markdown. Esc, or a click outside it, closes it.
import app from "ags/gtk4/app"
import Astal from "gi://Astal?version=4.0"
import Gtk from "gi://Gtk?version=4.0"
import { Panel } from "../lib/tui"
import { doc, closeDoc } from "../lib/alerts"
import { markdownToPango } from "../lib/markdown"
import { ROLE } from "../lib/palette"
import { closeKeys } from "../lib/keys"
import { clickawayField } from "./Clickaway"

export default function DocReader() {
  const keys = closeKeys({ close: closeDoc, q: true })
  return (
    <window
      $={(self) => self.add_controller(keys)}
      visible={doc((d) => d !== null)}
      cssClasses={["doc-reader"]}
      namespace="astal-shell-doc"
      name="doc"
      layer={Astal.Layer.OVERLAY}
      keymode={Astal.Keymode.ON_DEMAND}
      exclusivity={Astal.Exclusivity.IGNORE}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT}
      marginTop={36}
      marginLeft={48}
      application={app}
    >
      <overlay>
        <box
          cssClasses={["clickaway-field"]}
          hexpand
          vexpand
          $={(self) => clickawayField(self, closeDoc)}
        />
        <box $type="overlay" halign={Gtk.Align.CENTER} valign={Gtk.Align.FILL} marginTop={24} marginBottom={48}>
          <Panel title={doc((d) => d?.title ?? "")} cssClasses={["doc-sheet"]}>
            <scrolledwindow hscrollbarPolicy={Gtk.PolicyType.NEVER} vexpand widthRequest={860}>
              <label
                cssClasses={["doc-body"]}
                xalign={0}
                yalign={0}
                wrap
                selectable
                useMarkup
                label={doc((d) => (d ? markdownToPango(d.text, ROLE.body, ROLE.key) : ""))}
              />
            </scrolledwindow>
          </Panel>
        </box>
      </overlay>
    </window>
  )
}
