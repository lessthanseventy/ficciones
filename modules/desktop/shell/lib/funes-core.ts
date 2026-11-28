// The pure half of lib/funes.ts: the memory file as read.

export type Memory = { key: string; mode: string; title: string; sub?: string; count: number; last: number }

/** The memories a file's text holds: an entry that is not one is dropped, and text that is no JSON object holds none. */
export function load(text: string): Record<string, Memory> {
  let raw: unknown
  try { raw = JSON.parse(text) } catch { return {} }
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return {}
  return Object.fromEntries(Object.entries(raw).filter(([, m]) =>
    typeof m?.key === "string" && typeof m?.mode === "string" && typeof m?.title === "string" && typeof m?.count === "number" && typeof m?.last === "number"))
}
