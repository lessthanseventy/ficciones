declare module 'claude-code' {
  interface PluginState {
    'next-step': { suggestion: { label: string; text: string | null; argv: string[] | null }[] | null }
  }
}
