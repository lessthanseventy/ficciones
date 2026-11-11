// node --test lib/launcher-core.test.mjs (mise shell:test): how the launcher orders apps.
import { test } from "node:test"
import assert from "node:assert/strict"
import { order } from "./launcher-core.ts"

const app = (name, exec = name.toLowerCase(), words = [], used = 0) => ({ name, exec, words, used })
const names = (q, list) => order(q, list, (a) => a, (a) => a.used).map((a) => a.name)

test("a name that starts with what was typed comes before one that only contains it", () => {
  const list = [app("Garuda Toolbox"), app("Hardware Locality lstopo"), app("Dolphin")]
  assert.deepEqual(names("dol", list), ["Dolphin"])
  assert.deepEqual(names("o", [app("Floorp"), app("Obsidian")]), ["Obsidian", "Floorp"])
})

test("use breaks a tie between equal matches, and never lifts a worse match over a better one", () => {
  const list = [app("Slack", "slack", ["chat", "im"], 50), app("Discord", "discord", [], 1), app("Dolphin", "dolphin", [], 9)]
  assert.deepEqual(names("d", list), ["Dolphin", "Discord"])
})

test("a later word of the name matches from its start", () => {
  assert.deepEqual(names("spi", [app("Inspire"), app("Slay the Spire")]), ["Slay the Spire", "Inspire"])
})

test("the command and the entry's keywords find an app its name does not", () => {
  const list = [app("Volume Control", "pavucontrol"), app("Dolphin", "dolphin", ["File Manager", "files"])]
  assert.deepEqual(names("pavu", list), ["Volume Control"])
  assert.deepEqual(names("file", list), ["Dolphin"])
})

test("letters in order with gaps still find the name, after every closer match", () => {
  assert.deepEqual(names("dlph", [app("Dolphin"), app("Godot")]), ["Dolphin"])
  assert.deepEqual(names("gh", [app("GtkHash"), app("Ghostty")]), ["Ghostty", "GtkHash"])
})

test("case and what does not match at all", () => {
  assert.deepEqual(names("FLO", [app("Floorp")]), ["Floorp"])
  assert.deepEqual(names("zzz", [app("Floorp")]), [])
})

test("equal match and equal use: the shorter name, then the alphabet", () => {
  assert.deepEqual(names("st", [app("Steam Linux Runtime"), app("Stew"), app("Steam")]), ["Stew", "Steam", "Steam Linux Runtime"])
})
