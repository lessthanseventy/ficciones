// The one Escape. Esc closes every overlay; `q` too when the overlay has no text input.
import Gtk from "gi://Gtk?version=4.0"
import Gdk from "gi://Gdk?version=4.0"

export interface CloseKeys {
  /** closes the overlay */
  close: () => void
  /** `q` closes as well: only for an overlay with no text input */
  q?: boolean
  /** Esc does this instead of closing (stepwise back-out, cancelling an inline prompt); it owns the close */
  onEsc?: () => void
  /** any key closes (the cheatsheet) */
  any?: boolean
  /** CAPTURE phase: Esc arrives before a focused child can take it */
  capture?: boolean
  /** true = the key is not ours at all (a focused terminal keeps Esc), checked first */
  skip?: () => boolean
  /** every other key; return true if handled */
  onKey?: (kv: number, mods: number) => boolean
}

export function closeKeys(o: CloseKeys): Gtk.EventControllerKey {
  const k = new Gtk.EventControllerKey(o.capture ? { propagationPhase: Gtk.PropagationPhase.CAPTURE } : {})
  k.connect("key-pressed", (_, kv, __, mods) => {
    if (o.skip?.()) return false
    if (o.any || (o.q && kv === Gdk.KEY_q)) return o.close(), true
    if (kv === Gdk.KEY_Escape) return (o.onEsc ?? o.close)(), true
    return o.onKey?.(kv, mods) ?? false
  })
  return k
}
