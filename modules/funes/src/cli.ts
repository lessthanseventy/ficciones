import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDb } from './db.ts';
import { migrate } from './migrate.ts';
import { doctor } from './doctor.ts';

/**
 * Where the database lives, resolved from the environment only — no distro-isms,
 * no hardcoded home. FUNES_DB overrides everything; otherwise the XDG data dir,
 * defaulting to ~/.local/share. The machine, not the code, decides the path.
 */
export function resolveDbPath(env: Record<string, string | undefined>): string {
  if (env.FUNES_DB) return env.FUNES_DB;
  const dataHome = env.XDG_DATA_HOME ?? join(env.HOME ?? '', '.local', 'share');
  return join(dataHome, 'funes', 'wb.db');
}

/**
 * The command dispatcher, kept testable: it takes its argv, environment, and an
 * output sink explicitly, and returns an exit code instead of calling exit — so
 * a test can drive it without a subprocess.
 */
export async function run(
  argv: string[],
  env: Record<string, string | undefined>,
  out: (line: string) => void,
): Promise<number> {
  const cmd = argv[0];
  switch (cmd) {
    case 'doctor':
    case 'migrate': {
      const path = resolveDbPath(env);
      mkdirSync(dirname(path), { recursive: true });
      const db = openDb(path);
      try {
        const applied = migrate(db);
        const report = doctor(db);
        if (cmd === 'migrate') {
          out(`migrated ${applied} — schema at version ${report.schemaVersion}`);
          return 0;
        }
        out(`integrity: ${report.integrity}`);
        out(
          `schema: version ${report.schemaVersion} (latest available ${report.latestMigration})`,
        );
        out(`tables: ${report.tables.join(', ') || '(none)'}`);
        out(`db: ${path}`);
        const healthy = report.integrity === 'ok' && report.schemaVersion === report.latestMigration;
        return healthy ? 0 : 1;
      } finally {
        db.close();
      }
    }
    default:
      out(`unknown command: ${cmd ?? '(none)'}`);
      out('usage: funes <doctor|migrate>');
      return 2;
  }
}

// Entry point when invoked as a program (bin/funes); skipped when imported by tests.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  run(process.argv.slice(2), process.env, (line) => process.stdout.write(`${line}\n`)).then(
    (code) => process.exit(code),
  );
}
