declare module 'claude-code' {
  interface PluginState {
    'next-step': { suggestion: string | null }
  }
}
