// A virtualised column: Gtk.ListView over a Gio.ListStore, so only the rows on screen are
// widgets. `For` builds a widget per item and detaches/reattaches every one on each change —
// fine for a dozen rows, the lag at a thousand notices. Items are diffed by `id`; a row's
// widget is built once per item and kept on it across scrolls, so scrolling never re-renders.
import Gtk from "gi://Gtk?version=4.0"
import GObject from "gi://GObject?version=2.0"
import Gio from "gi://Gio?version=2.0"
import type { Accessor } from "ags"
import { onCleanup, createRoot } from "ags"

const Item = GObject.registerClass(
  { GTypeName: "FiccionesVListItem" },
  class Item extends GObject.Object {
    value: unknown
    key = ""
    widget: Gtk.Widget | null = null
    dispose: (() => void) | null = null
  },
)
type ItemT = InstanceType<typeof Item>

export function VList<T>({
  items,
  id,
  render,
  equal = Object.is,
  cssClasses = [],
}: {
  items: Accessor<T[]>
  id: (item: T) => string
  render: (item: T) => Gtk.Widget
  /** same id but a changed item: when this says they differ, the row's widget is rebuilt */
  equal?: (a: T, b: T) => boolean
  cssClasses?: string[]
}) {
  const store = new Gio.ListStore({ item_type: Item.$gtype })
  const byKey = new Map<string, ItemT>()

  const detach = (w: Gtk.Widget) => { const p = w.parent; if (p instanceof Gtk.Box) p.remove(w) }
  // each row's widget in its own root: accessors bound inside it are disposed with the row
  const build = (it: ItemT, v: T) => { it.dispose?.(); it.widget = createRoot((dispose) => { it.dispose = dispose; return render(v) }); it.widget.hexpand = true; return it.widget }
  const drop = (it: ItemT) => { if (it.widget) detach(it.widget); it.dispose?.(); it.dispose = null; it.widget = null }
  function sync(list: T[]) {
    const next: ItemT[] = []
    const keep = new Set<string>()
    for (const v of list) {
      const k = id(v)
      keep.add(k)
      let it = byKey.get(k)
      if (!it) { it = new Item(); it.key = k; byKey.set(k, it) }
      else if (it.widget && !equal(it.value as T, v)) {
        // changed in place (a group's count ticked): rebuild, swapping into the row if it is on screen
        const row = it.widget.parent
        detach(it.widget)
        build(it, v)
        if (row instanceof Gtk.Box) row.append(it.widget!)
      }
      it.value = v
      next.push(it)
    }
    for (const [k, it] of byKey) if (!keep.has(k)) { drop(it); byKey.delete(k) }
    // one items-changed for the whole list: the view rebinds only the rows it shows
    store.splice(0, store.get_n_items(), next)
  }
  sync(items.peek())
  const unsub = items.subscribe(() => sync(items.peek()))
  onCleanup(unsub)

  const factory = new Gtk.SignalListItemFactory()
  factory.connect("setup", (_, li: Gtk.ListItem) => { li.child = new Gtk.Box({ hexpand: true }); li.activatable = false; li.selectable = false })
  factory.connect("bind", (_, li: Gtk.ListItem) => {
    const it = li.item as ItemT
    if (!it.widget) build(it, it.value as T)
    detach(it.widget!)
    ;(li.child as Gtk.Box).append(it.widget!)
  })
  factory.connect("unbind", (_, li: Gtk.ListItem) => {
    const it = li.item as ItemT
    if (it.widget?.parent === li.child) (li.child as Gtk.Box).remove(it.widget)
  })

  return (
    <Gtk.ListView
      cssClasses={["vlist", ...cssClasses]}
      model={new Gtk.NoSelection({ model: store })}
      factory={factory}
      singleClickActivate={false}
    />
  )
}
