// Markdown as Pango markup, for reading a coworker's doc in the shell (surfaces/DocReader.tsx):
// headings, bold, italics, inline code, fenced code and tables in monospace, bullets. Not a full
// CommonMark parser — the docs are a planner's markdown, and anything unrecognised reads as text.

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

function inline(s: string): string {
  // code spans first, so nothing inside them is read as emphasis
  const codes: string[] = []
  let out = esc(s).replace(/`([^`]+)`/g, (_, c) => `\u0000${codes.push(c) - 1}\u0000`)
  out = out
    .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
    .replace(/(^|[^*\w])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, "<u>$1</u>")
  return out.replace(/\u0000(\d+)\u0000/g, (_, i) => `<tt>${codes[Number(i)]}</tt>`)
}

/** `text` (markdown) as Pango markup; `heading` and `code` are the colours those take */
export function markdownToPango(text: string, heading: string, code: string): string {
  const out: string[] = []
  let fenced = false
  for (const line of text.split("\n")) {
    if (line.startsWith("```")) { fenced = !fenced; continue }
    if (fenced || line.startsWith("|") || line.startsWith("    ")) { out.push(`<tt><span foreground="${code}">${esc(line)}</span></tt>`); continue }
    const h = line.match(/^(#{1,4})\s+(.*)$/)
    if (h) {
      const size = ["xx-large", "x-large", "large", "medium"][h[1].length - 1]
      out.push(`<span size="${size}" weight="bold" foreground="${heading}">${inline(h[2])}</span>`)
      continue
    }
    const li = line.match(/^(\s*)[-*]\s+(.*)$/)
    if (li) { out.push(`${li[1]}  •  ${inline(li[2])}`); continue }
    out.push(inline(line))
  }
  return out.join("\n")
}
