// generated from modules/desktop/theme/palette.nix — edit THAT, never this file. The palette as JS, for the one place CSS cannot reach: Pango markup in a label.
export const PALETTE = {
  amber: "#FFB000",
  green: "#33FF00",
  pink: "#F06CB4",
  cyan: "#33C7FF",
  lilac: "#B98AFF",
  chip: "#FFB000",
  red: "#FF6969",
  dim: "#B8994C",
} as const
export type Hue = keyof typeof PALETTE
export const HUES: Hue[] = ["amber", "green", "pink", "cyan", "lilac"]
/** roles (and coworker archetypes) for Cairo drawing; the live theme swaps them in place */
export const ROLE = {
  alarm: "#FF6969",
  assistant: "#B98AFF",
  attention: "#F06CB4",
  body: "#FFB000",
  borderInactive: "#7A5500",
  builder: "#33FF00",
  edge: "#2A2A2A",
  fieldInk: "#0A0A0A",
  ground: "#000000",
  inactive: "#B8994C",
  key: "#33C7FF",
  live: "#33FF00",
  meta: "#B4A5D6",
  panel: "#0D0D0D",
  planner: "#F06CB4",
  prose: "#C7C7C7",
  raised: "#1A1A1A",
  reviewer: "#FFB000",
  structure: "#B5651D",
  surveyor: "#33C7FF",
} as const
export type Role = keyof typeof ROLE
