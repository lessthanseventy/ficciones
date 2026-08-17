// The dense statusline — replaces pi's default thin footer with a 2-line bar that
// packs the things you glance at most: full model name (never truncated), context
// usage with a visual bar, session I/O, git branch, sandbox, and funes connection.
//
// Uses the footerData API for reactive git-branch updates and extension statuses, plus
// ctx.sessionManager / ctx.model / ctx.getContextUsage() for everything else.

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext, FooterData } from "./pi.ts";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// ── formatters ────────────────────────────────────────────────────────────────

function fmtTokens(n: number): string {
  if (n === 0) return "0";
  if (n < 1_000) return String(n);
  if (n < 1_000_000) return `${(n / 1_000).toFixed(1)}k`;
  return `${(n / 1_000_000).toFixed(1)}M`;
}

function fmtCost(c: number): string {
  if (c === 0) return "";
  if (c < 0.01) return `$${c.toFixed(4)}`;
  if (c < 1) return `$${c.toFixed(2)}`;
  return `$${c.toFixed(2)}`;
}

function fmtCwd(cwd: string): string {
  const home = process.env.HOME;
  if (home && cwd.startsWith(home)) return `~${cwd.slice(home.length)}`;
  return cwd;
}

// A 10-char context bar: ▓▓▓░░░░░░░  fills proportionally.
function contextBar(pct: number, width: number): string {
  const filled = Math.round((pct / 100) * width);
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

          // Session I/O
          let input = 0;
          let output = 0;
          let cost = 0;
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === "message" && e.message.role === "assistant") {
              const m = e.message as AssistantMessage;
              input += m.usage.input;
              output += m.usage.output;
              cost += m.usage.cost.total;
            }
          }
          const ioParts = [`↑${fmtTokens(input)}`, `↓${fmtTokens(output)}`];
          const costStr = fmtCost(cost);
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