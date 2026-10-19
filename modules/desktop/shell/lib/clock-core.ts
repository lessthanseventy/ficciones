// The rail's stacked clock lines from tlon's office clockFace (kit/eggs.ts: 404 at 4:04, π at
// 3:14): pure, so node can test it.

/** the hour and minute lines of a face; a joke face takes the first line alone */
export function railLines(face: string): [string, string] {
  const [hh, mm] = face.split(":")
  return [hh!, mm ?? ""]
}
