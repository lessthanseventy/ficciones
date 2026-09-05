import Hyprland from "gi://AstalHyprland"
import { createBinding, createComputed, type Accessor } from "ags"

export const hypr = Hyprland.get_default()

export const focusedWorkspace = createBinding(hypr, "focusedWorkspace")
export const focusedClient = createBinding(hypr, "focusedClient")

/** Workspaces 1..N sorted by id; special (negative) ones are hidden from the rail. */
export const workspaces: Accessor<Hyprland.Workspace[]> = createBinding(hypr, "workspaces")(
  (ws) => ws.filter((w) => w.id > 0).sort((a, b) => a.id - b.id),
)

/**
 * The focused window's column within the scrolling strip: columns are the distinct x origins
 * of mapped clients on the focused workspace, sorted. Returns [index, count], 0-based.
 */
export const column: Accessor<[number, number]> = createComputed(
  [focusedWorkspace, focusedClient, createBinding(hypr, "clients")],
  (ws, fc, clients) => {
    if (!ws) return [0, 0]
    const xs = [...new Set(
      clients.filter((c) => c.workspace?.id === ws.id && c.mapped && !c.floating).map((c) => c.x),
    )].sort((a, b) => a - b)
    const i = fc ? xs.indexOf(fc.x) : -1
    return [i, xs.length]
  },
)
