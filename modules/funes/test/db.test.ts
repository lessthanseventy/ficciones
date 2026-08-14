import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { openDb } from '../src/db.ts';

function tempDbPath(): { path: string; cleanup: () => void } {
  const dir = mkdtempSync(join(tmpdir(), 'funes-test-'));
  return { path: join(dir, 'wb.db'), cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

test('openDb opens a file database in WAL mode', () => {
  const { path, cleanup } = tempDbPath();
  const db = openDb(path);
  try {
    const row = db.prepare('PRAGMA journal_mode').get() as { journal_mode: string };
    assert.equal(row.journal_mode, 'wal');
  } finally {
    db.close();
    cleanup();
  }
});

test('openDb sets a bounded busy_timeout of 100ms (the write contract)', () => {
  const { path, cleanup } = tempDbPath();
  const db = openDb(path);
  try {
    const row = db.prepare('PRAGMA busy_timeout').get() as { timeout: number };
    assert.equal(row.timeout, 100);
  } finally {
    db.close();
    cleanup();
  }
});

test('openDb enforces foreign keys', () => {
  const { path, cleanup } = tempDbPath();
  const db = openDb(path);
  try {
    const row = db.prepare('PRAGMA foreign_keys').get() as { foreign_keys: number };
    assert.equal(row.foreign_keys, 1);
  } finally {
    db.close();
    cleanup();
  }
});
