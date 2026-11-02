// node --test lib/themePreview.test.mjs (mise shell:test): a theme's preview card.
import { test } from "node:test"
import assert from "node:assert/strict"
import { previewMarkup, PREVIEW_WIDTH } from "./themePreview.ts"

const p = {
  blurb: "ink & paper", ground: "#000001", card: "#000002", edge: "#000003", body: "#000004", key: "#000005", meta: "#000006",
  live: "#000007", attention: "#000008", warn: "#000009", alarm: "#00000a", field: "#00000b", fieldInk: "#00000c",
}
const text = (line) => line.replace(/<[^>]+>/g, "").replace(/&amp;/g, "&")

test("every line of the card is the same width", () => {
  for (const line of previewMarkup("babel", p).split("\n")) assert.equal(text(line).length, PREVIEW_WIDTH, line)
})

test("the card shows the theme's name and its colours", () => {
  const m = previewMarkup("babel", p)
  assert.match(m, /babel/)
  for (const c of [p.ground, p.card, p.edge, p.body, p.key, p.meta, p.live, p.attention, p.warn, p.alarm, p.field, p.fieldInk]) assert.ok(m.includes(c), c)
})

test("the blurb is escaped for Pango", () => {
  assert.match(previewMarkup("babel", p), /ink &amp; paper/)
})
