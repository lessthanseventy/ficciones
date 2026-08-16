// The honest brief (pi doc §2b). A pure function: funes' get_dossier JSON in, the
// prompt text a fresh session wakes to out. It is pure so it is testable, and so the
// wiring (extension.ts) can stay a thin transport around it.
//
// Two anti-laundering rules live here, because this is the one place a re-brief could
// launder a guess into ground truth:
//   1. Every claim shows its provenance. A `derived` fact with no check_cmd renders AS
//      a hunch — never as flat truth — so generation N's guess cannot become generation
//      N+1's received truth with no one lying at any step.
//   2. The brief states its own staleness and its cuts. "Last banked 40m ago; work
//      since is unrecorded" (§6: unrecorded time is named), and every capped section
//      carries its +N more (a cut without a count is the empty-world lie in miniature).

// The get_dossier shape — funes' Funes.MCP.Brief.scope/1 (one source, two protocol
// doors). Timestamps are ISO8601 strings or null; certainty is the read-time §4a rank.
export type Certainty = "stated" | "checked" | "opinion";

export interface Fact {
  id: number;
  kind: string;
  text: string;
  provenance: string;
  check_cmd: string | null;
  certainty: Certainty;
  at: string | null;
}

export interface Todo {
  id: number;
  text: string;
  done_at: string | null;
  at: string | null;
}

// One entry of the merged DONE view — a completed todo or a work_landed event, each at
// its own timestamp. Tagged by `source` so the render tells a finished step from a
// shipped outcome.
export type DoneEntry =
  | { source: "todo"; id: number; text: string; at: string | null }
  | {
      source: "event";
      id: number;
      kind: string;
      summary: string | null;
      evidence: string | null;
      at: string | null;
    };

export interface Blocker {
  id: number;
  summary: string;
  evidence: string | null;
  found_by: string | null;
  state: string;
  at: string | null;
}

export interface ChatterMessage {
  id: number;
  author: string;
  body: string;
  reply_to: number | null;
  at: string | null;
}

export interface Question {
  id: number;
  text: string;
  state: string;
  resolution: string | null;
  at: string | null;
}

export interface Capped<T> {
  shown: T[];
  more: number;
}

export interface Dossier {
  thread_id: number;
  north_star: string | null;
  lead: string | null;
  todos: Capped<Todo>;
  next: Todo | null;
  learnings: Capped<Fact>;
  unknowns: Capped<Question>;
  done: Capped<DoneEntry>;
  blockers: Capped<Blocker>;
  chatter: ChatterMessage[];
}

// The operator's handle, so a stated fact reads as HIS words. funes trusts only this
// author for `stated` provenance; the render names him for the reader.
const OPERATOR = "andrew";

const CHATTER_TAIL = 5;

export function renderBrief(d: Dossier, now: Date = new Date()): string {
  const lines: string[] = [];

  const goal = d.north_star ?? "(untitled thread)";
  lines.push(`# Brief: ${goal}`);
  lines.push(`Lead: ${d.lead ?? "unstaffed"}  ·  thread ${d.thread_id}`);
  lines.push(staleness(d, now));

  if (d.todos.shown.length > 0) {
    lines.push("", "## Plan  (→ is NEXT, the first open step)");
    for (const t of d.todos.shown) {
      const isNext = d.next != null && t.id === d.next.id;
      lines.push(`${isNext ? "→" : " "} [ ] ${t.text}`);
    }
    pushMore(lines, d.todos.more, "todos");
  }

  if (d.learnings.shown.length > 0) {
    lines.push("", "## What's known");
    for (const f of d.learnings.shown) lines.push(renderFact(f));
    pushMore(lines, d.learnings.more, "learnings");
  }

  if (d.unknowns.shown.length > 0) {
    lines.push("", "## Unknowns  (open questions — resolve or you inherit the doubt)");
    for (const q of d.unknowns.shown) lines.push(`- ? ${q.text}`);
    pushMore(lines, d.unknowns.more, "unknowns");
  }

  if (d.blockers.shown.length > 0) {
    lines.push("", "## Blockers");
    for (const b of d.blockers.shown) lines.push(renderBlocker(b));
    pushMore(lines, d.blockers.more, "blockers");
  }

  if (d.done.shown.length > 0) {
    lines.push("", "## Done");
    for (const e of d.done.shown) lines.push(renderDone(e));
    pushMore(lines, d.done.more, "done");
  }

  if (d.chatter.length > 0) {
    lines.push("", "## Recent chatter");
    for (const m of d.chatter.slice(-CHATTER_TAIL)) lines.push(`- ${m.author}: ${m.body}`);
  }

  return lines.join("\n");
}

// A fact, rendered by its read-time certainty — the marker is the honesty. A hunch is
// labelled a hunch and told to be re-checked; it never appears as a bare assertion. The
// default FAILS CLOSED: an `opinion`, OR any certainty funes ever emits that we don't
// model, degrades to the least-authoritative rendering — never an unmarked line, which
// would launder an unknown into apparent truth (the one thing this file exists to prevent).
function renderFact(f: Fact): string {
  switch (f.certainty) {
    case "stated":
      return `- [stated] ${OPERATOR}: "${f.text}"`;
    case "checked":
      return `- [checked] ${f.text}  (verify: \`${f.check_cmd}\`)`;
    default:
      return `- [hunch] ${f.text}  — unverified; re-check before you rely on it`;
  }
}

function renderBlocker(b: Blocker): string {
  const who = b.found_by ? `, found by ${b.found_by}` : "";
  const ev = b.evidence ? ` — ${b.evidence}` : "";
  return `- ${b.summary} (${b.state}${who})${ev}`;
}

function renderDone(e: DoneEntry): string {
  if (e.source === "todo") return `- [x] ${e.text}`;
  const ev = e.evidence ? ` — ${e.evidence}` : "";
  return `- ${e.summary ?? "(work landed)"}${ev}`;
}

function pushMore(lines: string[], more: number, noun: string): void {
  if (more > 0) lines.push(`_… and ${more} more ${noun} not shown (get_facts to read past the cap)._`);
}

// The staleness line: how old is the newest thing banked, and the honest warning that
// anything since is unrecorded. A thread with nothing banked says exactly that rather
// than rendering a confident empty world (§6: a cache that reports an empty world lies).
function staleness(d: Dossier, now: Date): string {
  const newest = newestAt(d);
  if (newest === null) {
    return "_Nothing has been banked on this thread yet — you are starting cold._";
  }
  return `_Last banked activity ${ago(newest, now)}; any work since is unrecorded._`;
}

function newestAt(d: Dossier): Date | null {
  const stamps: number[] = [];
  const collect = (at: string | null) => {
    if (!at) return;
    const t = Date.parse(at);
    if (!Number.isNaN(t)) stamps.push(t);
  };
  for (const f of d.learnings.shown) collect(f.at);
  for (const q of d.unknowns.shown) collect(q.at);
  for (const b of d.blockers.shown) collect(b.at);
  for (const e of d.done.shown) collect(e.at);
  for (const t of d.todos.shown) collect(t.at);
  for (const m of d.chatter) collect(m.at);
  if (stamps.length === 0) return null;
  return new Date(Math.max(...stamps));
}

// A stamp, never a clock (§4). Minutes up to 90, then hours, then days — enough for a
// reader to feel how stale the brief is without inventing precision.
function ago(then: Date, now: Date): string {
  const mins = Math.max(0, Math.round((now.getTime() - then.getTime()) / 60_000));
  if (mins < 90) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 48) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}
