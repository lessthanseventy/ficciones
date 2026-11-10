// generated from modules/desktop/theme/palettes/default.nix — edit THAT, never this file.
import type { Preview } from "./themePreview"
export const THEMES = ["babel", "hronir", "uqbar", "zahir"] as const
export type Theme = (typeof THEMES)[number]
/** a light ground: GTK's colour-scheme and the toggle's icon follow it */
export const LIGHT: Record<Theme, boolean> = { babel: true, hronir: false, uqbar: false, zahir: true }
/** the other half of a palette's family: what the toggle flips to */
export const PARTNER: Record<Theme, Theme> = { babel: "hronir", hronir: "babel", uqbar: "zahir", zahir: "uqbar" }
/** what a theme's card in Settings draws */
export const PREVIEWS: Record<Theme, Preview> = { babel: { blurb: "ink and graphite on paper", ground: "#F4ECDC", card: "#E8DEC8", edge: "#9A7A55", body: "#2C2A33", key: "#1A3F7C", meta: "#3C364F", live: "#274F18", attention: "#801F4D", warn: "#7A2E0D", alarm: "#801818", field: "#2C2A33", fieldInk: "#FFF9EC" }, hronir: { blurb: "chalk on a dark sketchbook", ground: "#23211D", card: "#2E2B26", edge: "#8E7456", body: "#EDE3CC", key: "#94C6F2", meta: "#CEC5E0", live: "#A3D98F", attention: "#F2A7C8", warn: "#F0A776", alarm: "#FFA9A2", field: "#EDE3CC", fieldInk: "#1C1A17" }, uqbar: { blurb: "amber phosphor on black", ground: "#000000", card: "#0E0E0E", edge: "#B5651D", body: "#FFB000", key: "#33C7FF", meta: "#B4A5D6", live: "#33FF00", attention: "#F06FB6", warn: "#FF720D", alarm: "#FF7575", field: "#FFB000", fieldInk: "#0A0A0A" }, zahir: { blurb: "the same tube in daylight", ground: "#F5EFE0", card: "#E6DCC6", edge: "#A86A2A", body: "#4E3300", key: "#09465A", meta: "#3D354F", live: "#144C14", attention: "#831252", warn: "#733200", alarm: "#7D1A15", field: "#4E3300", fieldInk: "#FFF7DD" } }
