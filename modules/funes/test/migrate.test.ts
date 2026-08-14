import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { openDb } from '../src/db.ts';
import { migrate } from '../src/migrate.ts';

function tempDb(): { db: ReturnType<typeof openDb>; cleanup: () => void } {
  const dir = mkdtempSync(join(tmpdir(), 'funes-test-'));
  const db = openDb(join(dir, 'wb.db'));
  return { db, cleanup: () => { db.close(); rmSync(dir, { recursive: true, force: true }); } };
}

function userVersion(db: ReturnType<typeof openDb>): number {
  return (db.prepare('PRAGMA user_version').get() as { user_version: number }).user_version;
}

test('migrate applies pending migrations and advances user_version', () => {
  const { db, cleanup } = tempDb();
  try {
    assert.equal(userVersion(db), 0, 'a fresh db starts at version 0');
    migrate(db);
    assert.ok(userVersion(db) >= 1, 'user_version advanced past 0');
  } finally {
    cleanup();
  }
});

test('migrate creates the collection table (the honesty table, §4)', () => {
  const { db, cleanup } = tempDb();
  try {
    migrate(db);
    const row = db
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='collection'")
      .get();
    assert.ok(row, 'collection table exists after migration');
  } finally {
    cleanup();
  }
});

test('migrate is idempotent — a second run applies nothing', () => {
  const { db, cleanup } = tempDb();
  try {
    const first = migrate(db);
    const second = migrate(db);
    assert.ok(first >= 1, 'first run applies at least one migration');
    assert.equal(second, 0, 'second run applies nothing');
  } finally {
    cleanup();
  }
});
