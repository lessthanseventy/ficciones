// The TUI primitives every surface is built from. Presentation lives in style/; these only fix
// the widget tree so one SCSS rule styles every instance the same way (design §3).
import Gtk from "gi://Gtk?version=4.0"
import type { Accessor } from "ags"
import type { JSX } from "ags/gtk4"

type Text = string | Accessor<string>

/** fieldset/legend: a 1px border with the title inset into the top edge. */
export function Panel({
  title,
  children,
  cssClasses = [],
  vertical = true,
}: {
  title: Text
  children?: JSX.Element | JSX.Element[]
  cssClasses?: string[]
  vertical?: boolean
}) {
  return (
    <overlay cssClasses={["panel", ...cssClasses]}>
      <box
        $type="overlay"
        halign={Gtk.Align.START}
        valign={Gtk.Align.START}
        canTarget={false}
      >
        <label cssClasses={["panel-title"]} label={title} />
      </box>
      <box
        orientation={vertical ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL}
      >
        {children}
      </box>
    </overlay>
  )
}

/** Inverse-video field: dark ink on the bright chip colour. */
export function Chip({ label, cssClasses = [] }: { label: Text; cssClasses?: string[] }) {
  return <label cssClasses={["chip", ...cssClasses]} label={label} />
}

/** `KEY val` on one line, key in chrome amber, value in body green. */
export function Stat({
  k,
  v,
  cssClasses = [],
}: {
  k: string
  v: Text
  cssClasses?: string[] | Accessor<string[]>
}) {
  return (
    <box cssClasses={cssClasses} spacing={0} hexpand={false} halign={Gtk.Align.START}>
      <label cssClasses={["k"]} label={k + " "} hexpand={false} />
      <label label={v} hexpand={false} />
    </box>
  )
}
