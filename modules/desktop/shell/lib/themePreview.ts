// A theme's card in Settings: a small window in its own colours, as Pango markup. Pure, so the
// markup is tested without GTK.
export type Preview = {
  blurb: string; ground: string; card: string; edge: string; body: string; key: string; meta: string
  live: string; attention: string; warn: string; alarm: string; field: string; fieldInk: string
}

export const PREVIEW_WIDTH = 28

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
const span = (bg: string, fg: string, text: string) => `<span background="${bg}" foreground="${fg}">${esc(text)}</span>`
const fit = (s: string) => s.slice(0, PREVIEW_WIDTH).padEnd(PREVIEW_WIDTH)

/** Every line is PREVIEW_WIDTH cells across, so in the mono font the card is a clean rectangle. */
export function previewMarkup(name: string, p: Preview): string {
  const on = (fg: string, text: string, pad = PREVIEW_WIDTH) => span(p.ground, fg, text.padEnd(pad))
  return [
    span(p.card, p.key, fit(` ${name}`)),
    on(p.ground, "", PREVIEW_WIDTH),
    on(p.body, " body text and a ", 17) + on(p.key, "link", PREVIEW_WIDTH - 17),
    on(p.live, " ok ", 4) + on(p.attention, "wait ", 5) + on(p.warn, "warn ", 5) + on(p.alarm, "alarm", PREVIEW_WIDTH - 14),
    on(p.ground, "", 1) + span(p.field, p.fieldInk, " active ") + on(p.ground, "", 1) + span(p.edge, p.ground, "    ") + on(p.ground, "", PREVIEW_WIDTH - 14),
    on(p.meta, fit(` ${p.blurb}`)),
  ].join("\n")
}
