// `astal-shell theme amber|paper|toggle`: write modules/desktop/theme/current, regenerate the
// checked-in palette files, home:switch (every surface: ghostty, GTK, Qt, floorp, hyprland…),
// then restart the shell on the new store bundle. Minutes, in the background; a notification
// at each end. Single-user machine, fixed checkout — the same assumption lib/agents.ts makes.
import GLib from "gi://GLib?version=2.0"
import { execAsync } from "ags/process"

const REPO = "/home/andrew/projects/ficciones"
const CURRENT = `${REPO}/modules/desktop/theme/current`
export const THEMES = ["amber", "paper"] as const
export type Theme = (typeof THEMES)[number]

export function currentTheme(): Theme {
  try {
    const [ok, bytes] = GLib.file_get_contents(CURRENT)
    const t = ok ? new TextDecoder().decode(bytes).trim() : "amber"
    return (THEMES as readonly string[]).includes(t) ? (t as Theme) : "amber"
  } catch { return "amber" }
}

let running = false
export function setTheme(t: Theme | "toggle") {
  const next: Theme = t === "toggle" ? (currentTheme() === "amber" ? "paper" : "amber") : t
  if (running) return
  running = true
  const script = [
    `cd ${REPO}`,
    `printf '%s\\n' ${next} > modules/desktop/theme/current`,
    `notify-send -a 'astal-shell' 'theme → ${next}' 'regenerating the palette and switching home… (a minute or two)'`,
    `mise theme:gen && mise home:switch && hyprctl reload`,
    `notify-send -a 'astal-shell' 'theme → ${next}' 'done — restarting the shell'`,
    `sleep 1; pkill -x gjs; sleep 0.5; astal-shell`,
  ].join(" && ")
  execAsync(["bash", "-lc", script])
    .catch((e) => execAsync(["notify-send", "-u", "critical", "-a", "astal-shell", `theme → ${next} failed`, String(e).slice(0, 400)]).catch(console.error))
    .finally(() => { running = false })
}
