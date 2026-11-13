import { execAsync } from "ags/process"

/**
 * Run `argv` in a systemd scope of its own. A program started as the shell's plain child stays in
 * astal-shell.service, and stopping or restarting the shell kills everything in that unit.
 */
export const outside = (argv: string[]) => execAsync(["systemd-run", "--user", "--scope", "--quiet", "--collect", "--", ...argv])

/** Start a desktop app (an AstalApps application) outside the shell's unit. */
export const launchApp = (a: { app: unknown }) => outside(["gio", "launch", (a.app as { filename: string }).filename]).then(() => void 0)
