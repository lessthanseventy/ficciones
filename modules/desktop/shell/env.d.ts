declare const SRC: string

declare module "inline:*" {
  const content: string
  export default content
}

declare module "*.scss" {
  const content: string
  export default content
}

declare module "*.blp" {
  const content: string
  export default content
}

declare module "*.css" {
  const content: string
  export default content
}

// office/kit (tlon's, shared with its bun TUI) names this in a default argument the shell never
// takes. gjs has no `process`: nothing of ours may read it.
declare const process: { env: Record<string, string | undefined> }
