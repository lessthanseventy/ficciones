// The palette as JS, for the one place CSS cannot reach: Pango markup inside a label. Mirrors
// style/_tokens.scss name for name — the §5b generator will emit both from palette.nix.
export const PALETTE = {
  amber: "#FFB000",
  green: "#33FF00",
  pink: "#E0218A",
  cyan: "#33C7FF",
  lilac: "#B98AFF",
  chip: "#FFD000",
} as const
export type Hue = keyof typeof PALETTE
export const HUES: Hue[] = ["amber", "green", "pink", "cyan", "lilac"]
