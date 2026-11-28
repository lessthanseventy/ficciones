// The pure half of lib/poll.ts.

/** `fn` for a poll: a throw or a rejection is logged and the poll keeps the value it had */
export function kept<T>(fn: (prev: T) => T | Promise<T>): (prev: T) => T | Promise<T> {
  return (prev) => {
    const lost = (e: unknown) => { console.error("poll:", e); return prev }
    try {
      const v = fn(prev)
      return v instanceof Promise ? v.catch(lost) : v
    } catch (e) { return lost(e) }
  }
}
