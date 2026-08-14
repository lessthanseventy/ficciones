import type { DatabaseSync } from 'node:sqlite';
import { loadMigrations } from './migrate.ts';

export interface DoctorReport {
  /** `ok`, or the first problem `PRAGMA integrity_check` found. */
  integrity: string;
  /** The schema version the database is actually at. */
  schemaVersion: number;
  /** The highest migration available on disk — a gap means unapplied migrations. */
  latestMigration: number;
  /** User tables present, sqlite internals excluded. */
  tables: string[];
}

/**
 * The 2am report. Ask the database itself whether it is sound (integrity_check),
 * what version it believes it is, and what tables it holds — the arbiter's own
 * answers, not our bookkeeping.
 */
export function doctor(db: DatabaseSync): DoctorReport {
  const integrity = (
    db.prepare('PRAGMA integrity_check').get() as { integrity_check: string }
  ).integrity_check;
  const schemaVersion = (db.prepare('PRAGMA user_version').get() as { user_version: number })
    .user_version;
  const latestMigration = loadMigrations().at(-1)?.version ?? 0;
  const tables = (
    db
      .prepare(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .all() as { name: string }[]
  ).map((row) => row.name);
  return { integrity, schemaVersion, latestMigration, tables };
}

/**
 * Export one table as JSONL — the escape hatch that makes the database
 * repairable with a text editor. The table name cannot be a bound parameter, so
 * it is validated against the live schema before it is ever interpolated: an
 * unknown name is refused, not run.
 */
export function tableToJsonl(db: DatabaseSync, table: string): string {
  const known = db
    .prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?")
    .get(table);
  if (!known) throw new Error(`no such table: ${table}`);
  return (db.prepare(`SELECT * FROM "${table}"`).all() as unknown[])
    .map((row) => JSON.stringify(row))
    .join('\n');
}
