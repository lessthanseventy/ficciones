// node --test lib/sfx-core.test.mjs (mise shell:test): the pure half of lib/sfx.ts.
import { test } from "node:test"
import assert from "node:assert/strict"
import { existsSync } from "node:fs"
import { sfxFile, mayPlay } from "./sfx-core.ts"

test("each sound is a WAV that ships in assets/sfx", () => {
  for (const name of ["decision", "landing", "timer"]) {
    const f = sfxFile(name, new URL("..", import.meta.url).pathname)
    assert.match(f, new RegExp(`assets/sfx/${name}\\.wav$`))
    assert.ok(existsSync(f), f)
  }
})

test("sounds play unless the setting is off or do-not-disturb is on", () => {
  assert.equal(mayPlay({ sfx: true, dnd: false }), true)
  assert.equal(mayPlay({ sfx: false, dnd: false }), false)
  assert.equal(mayPlay({ sfx: true, dnd: true }), false)
})
