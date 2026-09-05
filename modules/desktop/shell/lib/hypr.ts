import Hyprland from "gi://AstalHyprland"
import { createBinding, type Accessor } from "ags"

export const hypr = Hyprland.get_default()

export const focusedWorkspace = createBinding(hypr, "focusedWorkspace")
export const focusedClient = createBinding(hypr, "focusedClient")

/** Workspaces 1..N sorted by id; special (negative) ones are hidden from the rail. */
export const workspaces: Accessor<Hyprland.Workspace[]> = createBinding(hypr, "workspaces")(
  (ws) => ws.filter((w) => w.id > 0).sort((a, b) => a.id - b.id),
)
