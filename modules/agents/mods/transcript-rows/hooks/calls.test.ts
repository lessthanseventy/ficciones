import { expect, test } from 'claude-code/testing'

import { callText, lastSaid, menardSaid, patchCounts, shellEdits, steps, took, turnLine, whyFailed } from './calls'

test('a menard call is named by what it did', async () => {
  const reply = [{ type: 'text', text: '{"did":"edit cart.ex: 2 replacements","changed":[]}' }]
  expect(menardSaid({ tool: 'mcp__plugin_menard_menard__edit', input: { edits: [{ file: 'lib/cart.ex' }] }, output: reply })).toBe('edit cart.ex: 2 replacements')
  expect(menardSaid({ tool: 'mcp__plugin_menard_menard__edit', input: { edits: [{ file: 'lib/cart.ex', old: 'a', new: 'b' }] } })).toBe('edit lib/cart.ex')
  expect(menardSaid({ tool: 'mcp__plugin_menard_menard__edit', input: { edits: [{ file: '/home/u/repo/lib/menard/run/lock.ex' }, { file: 'lib/a.ex' }], then: 'compile' } })).toBe('edit run/lock.ex lib/a.ex · then compile')
  expect(menardSaid({ tool: 'Bash', input: { command: "cd x && ~/projects/menard/bin/menard edit - <<'EOF'\n…" }, output: { stdout: '{"did":"edit a.ts: 1 replacement"}' } })).toBe('edit a.ts: 1 replacement')
  expect(menardSaid({ tool: 'mcp__plugin_menard_menard__run', input: { verb: 'test' }, output: '{"ok":false,"failures":[]}' })).toBe('run test: failed')
  expect(menardSaid({ tool: 'Bash', input: { command: 'ls' }, output: {} })).toBeNull()
  expect(menardSaid({ tool: 'Bash', input: { command: 'git commit -m "menard said so"' }, output: {} })).toBeNull()
  expect(menardSaid({ tool: 'Bash', input: { command: "tmux send-keys 'run ~/bin/menard version'; sleep 1" }, output: {} })).toBeNull()
  expect(menardSaid({ tool: 'Bash', input: { command: 'menard outline lib/a.ex' }, output: { stdout: 'A\n  f/1 3-9\n' } })).toBe('outline lib/a.ex')
  expect(menardSaid({ tool: 'Bash', input: { command: 'menard edit - && mise run check' }, output: { stdout: '{"did":"edit a.ts: 1 replacement"}\n✓ exit 0' } })).toBeNull()
  expect(menardSaid({ tool: 'Read', input: { file_path: 'menard edit' } })).toBeNull()
})

test('a command that starts with menard and goes on is a shell command from the start', async () => {
  const edit = "cd /r && menard edit - <<'EOF'\na.ex\n<<<<<<< SEARCH\nx\n=======\ny\n>>>>>>> REPLACE\nEOF"
  expect(menardSaid({ tool: 'Bash', input: { command: edit } })).toBe('edit')
  expect(menardSaid({ tool: 'Bash', input: { command: `${edit}\ngit add . && git commit -m x` } })).toBeNull()
})

test('a call becomes a line a turn can be summarised from', async () => {
  expect(turnLine({ tool: 'Edit', input: { tool: 'Edit', file_path: 'lib/a.ts' }, output: { structuredPatch: [{ lines: ['-a', '+b', '+c'] }] } }, false)).toBe('Edit lib/a.ts +2 -1')
  expect(turnLine({ tool: 'Bash', input: { tool: 'Bash', command: 'mise run check\necho done' }, output: { stdout: 'building\n 3 fail\n' } }, true)).toBe('Bash mise run check (failed) → 3 fail')
  expect(turnLine({ tool: 'mcp__plugin_menard_menard__run', input: { verb: 'test' }, output: '{"ok":true}' }, false)).toBe('menard run test: ok')
})

test('a shell command of several steps is named by them', async () => {
  const command = [
    "cd /repo/mod && ~/projects/menard/bin/menard edit - <<'EOF'",
    'hooks/a.ts',
    'git commit -m "inside the heredoc; not a step"',
    'EOF',
    'cd /repo && git add mods && git commit -q -F - <<\'EOF\'',
    'a message && with; separators',
    'EOF',
    'mise run cap -- mise run check && git push -q origin main && systemd-run --user --scope -- mise run cap -- mise run home:switch >/dev/null; git status --short | head -3',
  ].join('\n')
  expect(steps(command)).toEqual(['menard edit', 'git add', 'git commit', 'mise run check', 'git push', 'mise run home:switch', 'git status'])
  expect(steps("S=/tmp/x; t() { tmux -L a \"$@\"; }; t kill-server; grep -n 'a; b' f | head")).toEqual(['grep'])
  expect(steps('ls src')).toEqual(['ls'])
  expect(turnLine({ tool: 'Bash', input: { command: 'git add . && git commit -m x' }, output: { stdout: 'ok\n' } }, false)).toBe('Bash git add · git commit → ok')
  const edits = { files: [{ filePath: '/r/a.ts', hunks: [{ lines: ['-a', '+b'] }] }, { filePath: '/r/b.ts', hunks: [{ lines: ['+c'] }] }] }
  expect(turnLine({ tool: 'Bash', input: { command: 'sed -i s/a/b/ a.ts b.ts' }, output: { stdout: 'ok\n', bashEditDiff: edits } }, false)).toBe('Bash sed -i s/a/b/ a.ts b.ts → ok')
})

test('a variable set from a command names that command, and a lone step drops its cd', async () => {
  expect(steps('a=$(grep -n "x" flake.nix | cut -d: -f1) && sed -i "${a}d" flake.nix')).toEqual(['grep', 'sed'])
  expect(turnLine({ tool: 'Bash', input: { command: 'cd ~/projects/tlon && grep -rn x lib' } }, false)).toBe('Bash grep -rn x lib')
})

test('a failed call says why in its first words', async () => {
  expect(whyFailed('Error: File does not exist. Note: your cwd is /r.\nmore')).toBe('Error: File does not exist. Note: your cwd is /r.')
  expect(whyFailed({ stdout: '', stderr: '\nls: cannot access x\n' })).toBe('ls: cannot access x')
  expect(whyFailed(undefined)).toBe('')
})

test("a command's last word is not its timing, and a call's own time reads short", async () => {
  expect(lastSaid('Ran 29 tests across 1 file. [3.52s]\n    Finished in 109.53s\n')).toBe('Ran 29 tests across 1 file.')
  expect(lastSaid('● done\n✻ Cogitated for 3s · done 12:49 AM\n')).toBe('● done')
  expect(lastSaid('0\t0\n')).toBe('0 0')
  expect(lastSaid('\x1b[38;5;82m●\x1b[39m done\x07\n')).toBe('● done')
  expect(lastSaid('real 0m1.2s\n')).toBe('')
  expect(lastSaid('  ✓ exit 0\n  more: tail -n 200 .logs/x.log\n')).toBe('✓ exit 0')
  expect(lastSaid('557:              xdg.config\n          )\n')).toBe('557: xdg.config')
  expect([took(undefined), took(400), took(3400), took(109_530)]).toEqual(['', '', '3s', '1m 50s'])
})

test('a command too long for its row is cut between words and says it was cut', async () => {
  const command = `ls ~/projects/thatch-shots | grep -v -E '^[0-9]{2}-.*-(top|iso)\\.png$'; rm ~/projects/thatch-shots/[0-9][0-9]-*-top.png ~/projects/thatch-shots/[0-9][0-9]-*-iso.png`
  const line = turnLine({ tool: 'Bash', input: { command } }, false)
  expect(line.endsWith(' …')).toBe(true)
  expect(command.startsWith(line.slice('Bash '.length, -' …'.length) + ' ')).toBe(true)
  expect(turnLine({ tool: 'Bash', input: { command: 'rm ~/projects/thatch-shots/a.png' } }, false)).toBe('Bash rm ~/projects/thatch-shots/a.png')
})

test('a call on an absolute path is named by the file and its folder', async () => {
  expect(turnLine({ tool: 'Read', input: { file_path: '/home/a/repo/lib/cart.ex' } }, false)).toBe('Read lib/cart.ex')
})

test('a call clicked open is its command and its reply, each cut to a screen', async () => {
  expect(callText({ tool: 'Bash', input: { command: 'ls' }, output: { stdout: 'a\nb\n', stderr: '' } })).toEqual(['$ ls', 'a', 'b'])
  expect(callText({ tool: 'Edit', input: { file_path: '/r/a.ts', old_string: 'a' }, output: { structuredPatch: [{ lines: ['-a', '+b'] }] } })).toEqual(['/r/a.ts', '-a', '+b'])
  const long = Array.from({ length: 40 }, (_, i) => `l${i}`).join('\n')
  expect(callText({ tool: 'Bash', input: { command: 'x' }, output: long }).at(-1)).toBe('… +10 lines')
})

test('the files a shell command changed are counted from its result', async () => {
  const output = { stdout: '', bashEditDiff: { files: [{ filePath: '/repo/lib/a.ts', hunks: [{ lines: [' x', '-a', '+b', '+c'] }] }] } }
  expect(shellEdits(output)).toEqual([{ name: 'a.ts', adds: 2, dels: 1 }])
  expect(shellEdits({ stdout: 'ok' })).toEqual([])
})

test('an edit is counted from its own result', async () => {
  expect(patchCounts({ structuredPatch: [{ lines: [' a', '-b', '+c', '+d'] }, { lines: ['-e'] }] })).toEqual({ adds: 2, dels: 2 })
  expect(patchCounts({ type: 'create', structuredPatch: [], content: 'a\nb\n' })).toEqual({ adds: 2, dels: 0 })
  expect(patchCounts(undefined)).toEqual({ adds: 0, dels: 0 })
})

test('control characters in a call are shown as characters the engine draws', async () => {
  expect(callText({ tool: 'Bash', input: { command: 'make\tall' }, output: { stdout: 'a\x1b[1mb\r\nc\x7f\x9b\n', stderr: '' } })).toEqual(['$ make    all', 'a␛[1mb', 'c␡�'])
  expect(callText({ tool: 'Edit', input: { file_path: '/r/Makefile' }, output: { structuredPatch: [{ lines: ['+\tcc'] }] } })).toEqual(['/r/Makefile', '+    cc'])
  expect(turnLine({ tool: 'Bash', input: { command: 'printf a\tb\x1b' } }, false)).toBe('Bash printf a    b␛')
})
