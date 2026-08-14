import { DatabaseSync } from 'node:sqlite';

/**
 * Open the funes database with the §4 write contract already in force:
 * WAL so one writer never blocks readers, a *bounded* busy_timeout so a held
 * lock fails fast and retryably instead of hanging a turn, and foreign keys on
 * so the schema's references are real rather than decorative.
 */
export function openDb(path: string): DatabaseSync {
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode = WAL');
  db.exec('PRAGMA busy_timeout = 100');
  db.exec('PRAGMA foreign_keys = ON');
  return db;
}
