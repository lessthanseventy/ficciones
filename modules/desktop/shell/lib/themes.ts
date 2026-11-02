// generated from modules/desktop/theme/palettes/default.nix — edit THAT, never this file.
import type { Preview } from "./themePreview"
export const THEMES = ["babel", "hronir", "uqbar", "zahir"] as const
export type Theme = (typeof THEMES)[number]
/** a light ground: GTK's colour-scheme and the toggle's icon follow it */
export const LIGHT: Record<Theme, boolean> = { babel: true, hronir: false, uqbar: false, zahir: true }
/** the other half of a palette's family: what the toggle flips to */
export const PARTNER: Record<Theme, Theme> = { babel: "hronir", hronir: "babel", uqbar: "zahir", zahir: "uqbar" }
/** what a theme's card in Settings draws */
export const PREVIEWS: Record<Theme, Preview> = { babel: { blurb: "ink and graphite on paper", ground: "#F4ECDC", card: "#E8DEC8", edge: "#9A7A55", body: "#2C2A33", key: "#1D468A", meta: "#463F5C", live: "#2A5419", attention: "#84204F", warn: "#80300E", alarm: "#961C1C", field: "#2C2A33", fieldInk: "#FFF9EC" }, hronir: { blurb: "chalk on a dark sketchbook", ground: "#23211D", card: "#2E2B26", edge: "#8E7456", body: "#EDE3CC", key: "#94C6F2", meta: "#CBC2DE", live: "#A3D98F", attention: "#F2A7C8", warn: "#EE9A62", alarm: "#FF8F86", field: "#EDE3CC", fieldInk: "#1C1A17" }, uqbar: { blurb: "amber phosphor on black", ground: "#000000", card: "#0E0E0E", edge: "#B5651D", body: "#FFB000", key: "#33C7FF", meta: "#B4A5D6", live: "#33FF00", attention: "#F06CB4", warn: "#FF6E06", alarm: "#FF6969", field: "#FFB000", fieldInk: "#0A0A0A" }, zahir: { blurb: "the same tube in daylight", ground: "#F5EFE0", card: "#E6DCC6", edge: "#A86A2A", body: "#573900", key: "#0B556E", meta: "#483E5D", live: "#175917", attention: "#95145D", warn: "#843A00", alarm: "#99201A", field: "#573900", fieldInk: "#FFF7DD" } }
