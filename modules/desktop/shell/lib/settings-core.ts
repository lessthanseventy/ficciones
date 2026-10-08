// The pure half of lib/settings.ts — no gi imports, so node can test it (lib/settings-core.test.mjs).

export type Value = boolean | number | string | string[]
export type Values = Record<string, Value>

const sameType = (def: Value, v: unknown) => Array.isArray(def) ? Array.isArray(v) : typeof v === typeof def

/** The file's text over the defaults: a known key of the default's type is taken (a list keeps
 * only its strings), any other known key keeps its default, unknown keys are kept aside to be
 * written back. A missing or malformed file reads as the defaults. */
export function load<V extends Values>(defaults: V, text: string | null): { values: V; extra: Record<string, unknown>; error: string | null } {
  const values = { ...defaults }, extra: Record<string, unknown> = {}
  if (text === null) return { values, extra, error: null }
  let raw: unknown
  try { raw = JSON.parse(text) } catch (e) { return { values, extra, error: `not JSON: ${e}` } }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return { values, extra, error: "not a JSON object" }
  for (const [k, v] of Object.entries(raw)) {
    if (!(k in defaults)) { extra[k] = v; continue }
    const def = defaults[k]
    if (!sameType(def, v)) continue
    ;(values as Values)[k] = Array.isArray(def) ? (v as unknown[]).filter((x): x is string => typeof x === "string") : (v as Value)
  }
  return { values, extra, error: null }
}

export const dump = (values: Values, extra: Record<string, unknown>) => JSON.stringify({ ...extra, ...values }, null, 2) + "\n"

/** `astal-shell set KEY TEXT`: TEXT read as the default's type; a list is comma-separated. */
export function parseCli(def: Value, text: string): Value | Error {
  if (Array.isArray(def)) return text.split(",").map((s) => s.trim()).filter(Boolean)
  if (typeof def === "boolean") {
    if (["on", "true", "yes", "1"].includes(text)) return true
    if (["off", "false", "no", "0"].includes(text)) return false
    return new Error(`expected on/off, got "${text}"`)
  }
  if (typeof def === "number") {
    const n = Number(text)
    return text.trim() !== "" && Number.isFinite(n) ? n : new Error(`expected a number, got "${text}"`)
  }
  return text
}
