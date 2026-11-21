// The pure half of the rail's clock: its face and the two stacked lines it is drawn as.

/** the clock's face: 404 at four minutes past four (the time cannot be found), π at 3:14, and on Pi Day 3.14 for half of each minute */
export function clockFace(now: Date): string {
  const h = now.getHours() % 12, m = now.getMinutes()
  if (h === 4 && m === 4) return "404"
  if (h === 3 && m === 14) return "π"
  if (now.getMonth() === 2 && now.getDate() === 14 && now.getSeconds() < 30) return "3.14"
  return `${String(now.getHours()).padStart(2, "0")}:${String(m).padStart(2, "0")}`
}

/** the hour and minute lines of a face; a joke face takes the first line alone */
export function railLines(face: string): [string, string] {
  const [hh, mm] = face.split(":")
  return [hh!, mm ?? ""]
}
