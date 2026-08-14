import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { openDb } from '../src/db.ts';
import { migrate } from '../src/migrate.ts';
import { doctor, tableToJsonl } from '../src/doctor.ts';

function tempDb(): { db: ReturnType<typeof openDb>; cleanup: () => void } {
  const dir = mkdtempSync(join(tmpdir(), 'funes-test-'));
  const db = openDb(join(dir, 'wb.db'));
  return { db, cleanup: () => { db.close(); rmSync(dir, { recursive: true, force: true }); } };
}

test('doctor reports integrity ok and the current schema version', () => {
  const { db, cleanup } = tempDb();
  try {
    migrate(db);
    const report = doctor(db);
    assert.equal(report.integrity, 'ok');
    assert.equal(report.schemaVersion, 1);
    assert.equal(report.latestMigration, 1);
  } finally {
    cleanup();
  }
});

test('doctor lists the user tables and excludes sqlite internals', () => {
  const { db, cleanup } = tempDb();
  try {
    migrate(db);
    assert.deepEqual(doctor(db).tables, ['collection']);
  } finally {
    cleanup();
  }
});

test('tableToJsonl emits one JSON object per row — and can prove it returns something', () => {
  const { db, cleanup } = tempDb();
  try {
    migrate(db);
    db.prepare('INSERT INTO collection (source, last_attempt) VALUES (?, ?)').run(
      'github-prs',
      '2026-08-14T00:00:00Z',
    );
    const lines = tableToJsonl(db, 'collection').trim().split('\n').filter(Boolean);
    assert.equal(lines.length, 1, 'a row that exists must appear — no false empty');
    assert.deepEqual(JSON.parse(lines[0]!), {
      source: 'github-prs',
      last_attempt: '2026-08-14T00:00:00Z',
      last_success: null,
      last_error: null,
    });
  } finally {
    cleanup();
  }
});

test('tableToJsonl on an empty table is empty, not an error', () => {
  const { db, cleanup } = tempDb();
  try {
    migrate(db);
    assert.equal(tableToJsonl(db, 'collection'), '');
  } finally {
    cleanup();
  }
});

test('tableToJsonl refuses an unknown table rather than interpolating it', () => {
  const { db, cleanup } = tempDb();
  try {
    migrate(db);
    assert.throws(() => tableToJsonl(db, 'collection; DROP TABLE collection'), /no such table/);
  } finally {
    cleanup();
  }
});
