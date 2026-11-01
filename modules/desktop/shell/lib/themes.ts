// generated from modules/desktop/theme/palettes/default.nix — edit THAT, never this file.
export const THEMES = ["babel", "hronir", "uqbar", "zahir"] as const
export type Theme = (typeof THEMES)[number]
/** a light ground: GTK's colour-scheme and the toggle's icon follow it */
export const LIGHT: Record<Theme, boolean> = { babel: true, hronir: false, uqbar: false, zahir: true }
/** the other half of a palette's family: what the toggle flips to */
export const PARTNER: Record<Theme, Theme> = { babel: "hronir", hronir: "babel", uqbar: "zahir", zahir: "uqbar" }
