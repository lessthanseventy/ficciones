import type { DatabaseSync } from 'node:sqlite';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const MIGRATIONS_DIR = fileURLToPath(new URL('./migrations/', import.meta.url));

interface Migration {
  version: number;
  name: string;
  sql: string;
}

/**
 * Load the numbered .sql migrations from disk, ordered. The leading integer is
 * the schema version it brings the database to; SQLite's own `user_version` is
 * the ledger, so there is no bookkeeping table of ours to drift.
 */
export function loadMigrations(): Migration[] {
  return readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql'))
    .map((f) => {
      const match = /^(\d+)-/.exec(f);
      if (!match) throw new Error(`migration file has no leading version number: ${f}`);
      return { version: Number(match[1]), name: f, sql: readFileSync(MIGRATIONS_DIR + f, 'utf8') };
    })
    .sort((a, b) => a.version - b.version);
}

/**
 * Apply every migration newer than the database's current `user_version`, each
 * in its own transaction so a failure rolls back whole and leaves the version
 * untouched. Returns the count applied — zero when already current, which is
 * what makes a second call a safe no-op.
 */
export function migrate(db: DatabaseSync): number {
  const current = (db.prepare('PRAGMA user_version').get() as { user_version: number }).user_version;
  const pending = loadMigrations().filter((m) => m.version > current);
  let applied = 0;
  for (const m of pending) {
    db.exec('BEGIN');
    try {
      db.exec(m.sql);
      // user_version takes an integer literal, not a bound parameter; m.version
      // is a parsed Number, so there is nothing to inject.
      db.exec(`PRAGMA user_version = ${m.version}`);
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw new Error(`migration ${m.name} failed and was rolled back`, { cause: error });
    }
    applied++;
  }
  return applied;
}
