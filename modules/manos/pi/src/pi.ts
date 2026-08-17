// The slice of pi's ExtensionAPI that manos actually uses — hand-declared against pi's
// documented surface (github.com/earendil-works/pi, packages/coding-agent/docs), and
// deliberately minimal: it names exactly the hooks and ctx methods this adapter depends
// on, so a change in what we rely on is a change to THIS file. When pi publishes its own
// types, this is what to replace with them. Type-only — erased at runtime.

import type { AssistantMessage } from "@earendil-works/pi-ai";

export interface FooterData {
  getGitBranch(): string | null;
  getExtensionStatuses(): ReadonlyMap<string, string>;
  onBranchChange(cb: () => void): () => void;
}

export interface FooterComponent {
  render(width: number): string[];
  invalidate(): void;
  dispose?: () => void;
}

export interface ContextUsage {
  tokens: number;
  percent: number | null;
  contextWindow: number;
}

export interface Model {
  id: string;
  provider: string;
  contextWindow: number;
}

export interface ExtensionUI {
  // A one-line footer status (keyed; re-call to replace).
  setStatus(key: string, text: string): void;
  // A multi-line block above the editor (keyed; re-call with the same key to update).
  setWidget(key: string, lines: string[]): void;
  // A transient toast.
  notify(message: string, level?: "info" | "warning" | "error"): void;
  // Replace the built-in footer with a custom component.
  setFooter(factory: ((tui: TUI, theme: Theme, footerData: FooterData) => FooterComponent) | undefined): void;
  theme: Theme;
}

export interface TUI {
  requestRender(): void;
}

export interface Theme {
  fg(color: string, text: string): string;
  bg(color: string, text: string): string;
  bold(text: string): string;
}

export interface SessionManager {
  getEntries(): SessionEntry[];
  getBranch(): SessionEntry[];
}

export interface SessionEntry {
  type: string;
  message: AssistantMessage;
}

export interface ExtensionContext {
  ui: ExtensionUI;
  cwd: string;
  model: Model | undefined;
  sessionManager: SessionManager;
  getContextUsage(): ContextUsage | null;
}

export interface SessionStartEvent {
  // "startup" | "reload" | "new" | "resume" | "fork"
  reason: string;
  previousSessionFile?: string;
}

export interface BeforeAgentStartEvent {
  prompt: string;
  systemPrompt: string;
}

// A message injected into the session and sent to the model — the brief's vehicle.
export interface InjectedMessage {
  customType: string;
  content: string;
  display?: boolean;
}

export interface BeforeAgentStartResult {
  message?: InjectedMessage;
  systemPrompt?: string;
}

export interface ExtensionAPI {
  on(
    event: "session_start",
    handler: (event: SessionStartEvent, ctx: ExtensionContext) => void | Promise<void>,
  ): void;
  on(
    event: "before_agent_start",
    handler: (
      event: BeforeAgentStartEvent,
      ctx: ExtensionContext,
    ) => BeforeAgentStartResult | undefined | Promise<BeforeAgentStartResult | undefined>,
  ): void;
  on(event: "turn_end", handler: (event: unknown, ctx: ExtensionContext) => void | Promise<void>): void;
  getThinkingLevel(): string;
}
