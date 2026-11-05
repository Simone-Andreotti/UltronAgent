export type RunningLead = {
  label: string
  model: string
  effort?: string | number
}

declare module 'claude-code' {
  interface PluginState {
    leads: { running: RunningLead | null }
  }
}
