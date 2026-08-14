import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { resolveDbPath, run } from '../src/cli.ts';

test('resolveDbPath prefers FUNES_DB when set', () => {
  assert.equal(resolveDbPath({ FUNES_DB: '/tmp/x.db', HOME: '/home/a' }), '/tmp/x.db');
});

test('resolveDbPath falls back to XDG_DATA_HOME', () => {
  assert.equal(resolveDbPath({ XDG_DATA_HOME: '/data', HOME: '/home/a' }), '/data/funes/wb.db');
});

test('resolveDbPath falls back to ~/.local/share — no distro-isms, no hardcoded home', () => {
  assert.equal(resolveDbPath({ HOME: '/home/a' }), '/home/a/.local/share/funes/wb.db');
});

test('funes doctor migrates, reports ok, and exits 0 on a healthy db', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'funes-cli-'));
  const out: string[] = [];
  try {
    const code = await run(['doctor'], { FUNES_DB: join(dir, 'sub', 'wb.db') }, (line) => out.push(line));
    const text = out.join('\n');
    assert.equal(code, 0, text);
    assert.match(text, /integrity.*ok/i);
    assert.match(text, /collection/);
    assert.ok(existsSync(join(dir, 'sub', 'wb.db')), 'doctor created the db and its parent dir');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('an unknown command exits non-zero with a usage line', async () => {
  const out: string[] = [];
  const code = await run(['wat'], { HOME: '/home/a' }, (line) => out.push(line));
  assert.notEqual(code, 0);
  assert.match(out.join('\n'), /usage/i);
});
