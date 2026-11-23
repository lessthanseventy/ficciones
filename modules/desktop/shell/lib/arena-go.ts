// Sending the human somewhere goes through arena's command interface (arena show/board/inbox),
// so the running arena follows. Pure: the process, the terminal and the notice are handed in.
export const NO_ARENA = 3

export type Go = {
  /** runs argv, resolves with its exit status, rejects if it cannot start */
  run: (argv: string[]) => Promise<number>
  /** opens a terminal on arena: nothing was running to tell */
  open: () => void
  /** says it where the human will see it */
  notify: (text: string) => void
  /** says it where the next reader of the log will find it */
  log: (text: string) => void
}

/** Tell the running arena `args`; exit 3 means none is running, so `open` starts one. */
export async function tellArena(args: string[], go: Go) {
  const said = `arena ${args.join(" ")}`
  try {
    const code = await go.run(["arena", ...args])
    if (code === 0) return
    if (code === NO_ARENA) return go.open()
    go.log(`${said} exited ${code}`)
    go.notify(`${said} failed (exit ${code})`)
  } catch (e) {
    go.log(`${said}: ${String(e)}`)
    go.notify(`${said} failed: ${String(e)}`)
  }
}

export type Shell = Go & {
  /** the open arena window, if any */
  arena: () => { address: string } | undefined
  focus: (address: string) => void
}

/** Focus the open arena window, then tell it `args`. */
export function toArena(args: string[], open: () => void, sh: Shell) {
  const arena = sh.arena()
  if (arena) sh.focus(arena.address)
  return tellArena(args, { ...sh, open })
}
