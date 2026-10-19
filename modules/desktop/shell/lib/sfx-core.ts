// The pure half of lib/sfx.ts: which file a sound is, and whether it may play.
export type Sfx = "decision" | "landing" | "timer"

const FILES: Record<Sfx, string> = { decision: "decision.wav", landing: "landing.wav", timer: "timer.wav" }

/** the WAV for a sound, under the shell's source dir (`SRC` in the bundle, the working dir under `ags run`) */
export const sfxFile = (name: Sfx, src: string) => `${src}/assets/sfx/${FILES[name]}`

/** do-not-disturb mutes sounds as it mutes toasts */
export const mayPlay = (s: { sfx: boolean; dnd: boolean }) => s.sfx && !s.dnd
