/** The rows a PNG takes drawn `columns` wide, from the file's first 24 bytes; null when they hold no size. */
export function rowsFor(head: Uint8Array, columns: number): number | null {
  // a PNG's IHDR holds its width and height, big-endian, at bytes 16 and 20
  const at = (i: number) => head[i] ?? 0
  const width = (at(16) << 24) | (at(17) << 16) | (at(18) << 8) | at(19)
  const height = (at(20) << 24) | (at(21) << 16) | (at(22) << 8) | at(23)

  if (width < 1 || height < 1) {
    return null
  }

  // a terminal cell is about twice as tall as it is wide
  return Math.max(1, Math.min(60, Math.round((columns * height) / width / 2)))
}
