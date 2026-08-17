// The dense statusline — replaces pi's default thin footer with a 2-line bar that
// packs the things you glance at most: full model name (never truncated), context
// usage with a visual bar, session I/O, git branch, sandbox, and funes connection.
//
// A generic statusline: NOT a funes concern, so it lives in its own manos package (not
// modules/manos/pi, which the Tlön coworker profile drops to sever funes) — the footer
// loads for every pi, funes-citizen or self-contained.
//
// Uses the footerData API for reactive git-branch updates and extension statuses, plus
// ctx.sessionManager / ctx.model / ctx.getContextUsage() for everything else.

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext, FooterData } from "./pi.ts";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// ── formatters (pure — exported so the seams are unit-pinned) ───────────────────

export function fmtTokens(n: number): string {
  if (n === 0) return "0";
  if (n < 1_000) return String(n);
  if (n < 1_000_000) return `${(n / 1_000).toFixed(1)}k`;
  return `${(n / 1_000_000).toFixed(1)}M`;
}

export function fmtCost(c: number): string {
  if (c === 0) return "";
  if (c < 0.01) return `$${c.toFixed(4)}`;
  return `$${c.toFixed(2)}`;
}

// The usage fields the footer glances at, cache included. Structural (not the full pi-ai
// `Usage`) so the seam is unit-pinnable without constructing whole AssistantMessages.
export interface UsageLike {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  cost: { total: number };
}

export interface UsageTotals {
  input: number;
  output: number;
  cost: number;
  cacheRead: number;
  cacheWrite: number;
}

// Fold the per-turn usages into session totals. Extends the old inline input/output/cost
// sum with the cache read/write tokens that were already sitting unused on every Usage.
export function accumulateUsage(usages: Iterable<UsageLike>): UsageTotals {
  const totals: UsageTotals = { input: 0, output: 0, cost: 0, cacheRead: 0, cacheWrite: 0 };
  for (const u of usages) {
    totals.input += u.input;
    totals.output += u.output;
    totals.cost += u.cost.total;
    totals.cacheRead += u.cacheRead;
    totals.cacheWrite += u.cacheWrite;
  }
  return totals;
}

// Share of prompt tokens served from cache: cacheRead / (input + cacheRead + cacheWrite),
// rounded to a whole percent. Zero prompt tokens → 0 (no divide-by-zero). High is good —
// it's the reuse signal the cache-reuse cribs care about.
export function cacheHitPct(input: number, cacheRead: number, cacheWrite: number): number {
  const prompt = input + cacheRead + cacheWrite;
  if (prompt === 0) return 0;
  return Math.round((cacheRead / prompt) * 100);
}

export function fmtCwd(cwd: string): string {
  const home = process.env.HOME;
  if (home && cwd.startsWith(home)) return `~${cwd.slice(home.length)}`;
  return cwd;
}

// A context bar: ▓▓▓░░░░░░░  fills proportionally. Clamps pct to [0, 100] so context overflow
// (pct > 100) can't produce a negative repeat count (a crash in String.repeat).
export function contextBar(pct: number, width: number): string {
  const clamped = Math.max(0, Math.min(100, pct));
  const filled = Math.round((clamped / 100) * width);
  return "▓".repeat(filled) + "░".repeat(width - filled);
}

// ── the footer component ─────────────────────────────────────────────────────

export default function footer(pi: ExtensionAPI): void {
  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsubBranch = footerData.onBranchChange(() => tui.requestRender());
      // Extension statuses are reactive through the footer render — no extra sub needed,
      // but force a re-render if statuses change.
      // footerData.getExtensionStatuses() already reflects live setStatus() calls.

      let cachedWidth: number | undefined;
      let cachedLines: string[] | undefined;

      return {
        dispose: unsubBranch,
        invalidate() {
          cachedWidth = undefined;
          cachedLines = undefined;
        },
        render(width: number): string[] {
          // Cache-bust on width change; content changes are handled by invalidate
          // or by tui.requestRender() from reactive subscriptions.
          if (cachedLines && cachedWidth === width) return cachedLines;
          cachedWidth = width;

          const lines: string[] = [];

          // ── Line 1: model · provider │ context │ I/O ────────────────────
          const model = ctx.model;
          const modelId = model?.id ?? "no-model";
          const provider = model?.provider ?? "";
          const thinking = pi.getThinkingLevel();

          // Context usage
          const usage = ctx.getContextUsage();
          const ctxWindow = usage?.contextWindow ?? model?.contextWindow;
          const ctxPct = usage?.percent ?? 0;
          const ctxBarW = Math.min(10, Math.max(6, width - 40));
          const ctxLabel =
            ctxWindow && ctxPct !== null
              ? `${contextBar(ctxPct, ctxBarW)} ${Math.round(ctxPct)}%/${fmtTokens(ctxWindow)}`
              : "ctx ?";

          // Session I/O + cache — one fold over the branch's assistant usages.
          const usages: UsageLike[] = [];
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === "message" && e.message.role === "assistant") {
              usages.push((e.message as AssistantMessage).usage);
            }
          }
          const totals = accumulateUsage(usages);
          const ioParts = [`↑${fmtTokens(totals.input)}`, `↓${fmtTokens(totals.output)}`];
          // Cache reuse: only worth showing once cache is actually in play, else it reads
          // as a permanent 0% on providers/sessions that don't cache.
          if (totals.cacheRead > 0 || totals.cacheWrite > 0) {
            ioParts.push(`↺${cacheHitPct(totals.input, totals.cacheRead, totals.cacheWrite)}%`);
          }
          const costStr = fmtCost(totals.cost);
          if (costStr) ioParts.push(costStr);
          const ioLabel = ioParts.join(" ");

          const thinkLabel = thinking !== "off" ? ` · ${thinking}` : "";

          const line1Left = theme.fg("accent", `${modelId}`) + theme.fg("dim", `${provider ? ` · ${provider}` : ""}${thinkLabel}`);
          const line1Right = theme.fg("muted", `${ctxLabel} │ ${ioLabel}`);

          const pad1 = Math.max(1, width - visibleWidth(line1Left) - visibleWidth(line1Right));
          lines.push(truncateToWidth(line1Left + " ".repeat(pad1) + line1Right, width));

          // ── Line 2: cwd (branch) │ statuses ──────────────────────────────
          const branch = footerData.getGitBranch();
          const cwd = fmtCwd(ctx.cwd);

          // Shrink cwd to fit: keep at least branch + "…"
          const branchStr = branch ? ` (${branch})` : "";
          const locBase = `${cwd}${branchStr}`;

          // Extension statuses — funes, sandbox, etc.
          const statuses = footerData.getExtensionStatuses();
          const statusParts: string[] = [];
          statuses.forEach((text, key) => {
            // Both funes and sandbox statuses are self-describing — the text
            // already reads as "funes: registered..." or "🔒 Sandbox: 12 domains...".
            // Other keys get the key as prefix for context.
            const label = key === "funes" || key === "sandbox" ? text : `${key}: ${text}`;
            statusParts.push(label);
          });
          const statusStr = statusParts.length > 0 ? statusParts.join(" │ ") : "";

          const line2Left = theme.fg("dim", locBase);
          const line2Right = statusStr ? theme.fg("dim", statusStr) : "";

          if (line2Right) {
            const pad2 = Math.max(1, width - visibleWidth(line2Left) - visibleWidth(line2Right));
            lines.push(truncateToWidth(line2Left + " ".repeat(pad2) + line2Right, width));
          } else {
            lines.push(truncateToWidth(line2Left, width));
          }

          cachedLines = lines;
          return lines;
        },
      };
    });
  });
}
