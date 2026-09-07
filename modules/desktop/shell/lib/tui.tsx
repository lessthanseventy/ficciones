// The TUI primitives every surface is built from. Presentation lives in style/; these only fix
// the widget tree so one SCSS rule styles every instance the same way (design §3).
import Gtk from "gi://Gtk?version=4.0"
import type { Accessor } from "ags"

type Text = string | Accessor<string>
type Classes = string[] | Accessor<string[]>

// a mapped array among sibling children is an array inside the children array; gnim flattens
type Children = JSX.Element | Children[]

/** fieldset/legend: a 1px border with the title inset into the top edge. */
export function Panel({
  title,
  children,
  cssClasses = [],
  vertical = true,
  spacing = 0,
  visible,
  hexpand = false,
  vexpand = false,
}: {
  title: Text
  children?: Children
  cssClasses?: Classes
  vertical?: boolean
  spacing?: number
  visible?: Accessor<boolean>
  hexpand?: boolean
  vexpand?: boolean
}) {
  const classes =
    typeof cssClasses === "function" ? cssClasses((c) => ["panel", ...c]) : ["panel", ...cssClasses]
  return (
    <overlay cssClasses={classes} visible={visible ?? true} hexpand={hexpand} vexpand={vexpand}>
      <box $type="overlay" halign={Gtk.Align.START} valign={Gtk.Align.START} canTarget={false}>
        <label cssClasses={["panel-title"]} label={title} />
      </box>
      <box
        cssClasses={["panel-body"]}
        orientation={vertical ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL}
        spacing={spacing}
      >
        {children as JSX.Element | JSX.Element[]}
      </box>
    </overlay>
  )
}

/** Inverse-video field: dark ink on the bright chip colour. */
export function Chip({ label, cssClasses = [] }: { label: Text; cssClasses?: string[] }) {
  return <label cssClasses={["chip", ...cssClasses]} label={label} />
}

/** `KEY val` on one line: dim key, body value. `low`/`live` classes recolour the value. */
export function Stat({ k, v, cssClasses = [] }: { k: string; v: Text; cssClasses?: Classes }) {
  const classes =
    typeof cssClasses === "function" ? cssClasses((c) => ["stat", ...c]) : ["stat", ...cssClasses]
  return (
    <box cssClasses={classes} hexpand={false} halign={Gtk.Align.START}>
      <label cssClasses={["k"]} label={k} />
      <label cssClasses={["v"]} label={v} />
    </box>
  )
}

/** 1px separators for the cell grid. */
export const RuleV = ({ visible }: { visible?: Accessor<boolean> } = {}) => <box cssClasses={["rule-v"]} visible={visible ?? true} />
export const RuleH = ({ visible }: { visible?: Accessor<boolean> } = {}) => <box cssClasses={["rule-h"]} visible={visible ?? true} />
