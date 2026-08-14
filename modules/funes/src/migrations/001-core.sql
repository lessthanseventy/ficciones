-- 001-core.sql — the day-one core (spec §9.1).
--
-- Step one ships the database, migrations, and doctor, and nothing else until
-- this can be repaired at 2am. The only domain table it needs is `collection`:
-- without it, "the world is empty" cannot be told from "this collector has
-- failed three times" (§4, §6), and every later honesty rule leans on that
-- distinction. The remaining tables (fact, event, issue, signal, channel)
-- arrive in their own numbered migrations as their §9 step lands, which is how
-- the runner gets proven instead of shipped on faith.
--
-- Times are ISO-8601 TEXT stamps. Age and staleness are computed in the query,
-- never stored (§4: a field computed at write time is not a fact at read time).

CREATE TABLE collection (
  source        TEXT PRIMARY KEY,
  last_attempt  TEXT,
  last_success  TEXT,
  last_error    TEXT
);
