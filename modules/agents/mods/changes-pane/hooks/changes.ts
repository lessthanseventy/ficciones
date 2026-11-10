export type File = { path: string; isUntracked: boolean }
export type Commit = { sha: string; subject: string }
export type DiffLine = { text: string; hunk: number }
export type Run = { t: string; c?: string; b?: string; bold?: true; dim?: true; it?: true; u?: true }

export const parseStatus = (z: string): File[] => {
  const entries = z.split('\0')
  const files: File[] = []
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i]!
    if (entry.length <= 3) continue
    const [x, y] = [entry[0]!, entry[1]!]
    files.push({ path: entry.slice(3), isUntracked: x === '?' })
    // -z puts a rename's origin in an entry of its own.
    if (x === 'R' || x === 'C' || y === 'R' || y === 'C') i++
  }
  return files
}

// One `sha<TAB>subject` line per commit.
export const parseLog = (out: string): Commit[] =>
  out.split('\n').filter(line => line.includes('\t')).map(line => {
    const tab = line.indexOf('\t')
    return { sha: line.slice(0, tab), subject: line.slice(tab + 1) }
  })

type Patched = { structuredPatch?: { lines: string[] }[]; type?: string; content?: string }

// What an Edit or a Write did, counted from its own result; a new file has no patch, only content.
export const patchCounts = (output: unknown): { adds: number; dels: number } => {
  const { structuredPatch = [], type, content = '' } = (output ?? {}) as Patched
  const lines = structuredPatch.flatMap(hunk => hunk.lines)
  if (lines.length === 0 && type === 'create') return { adds: content.replace(/\n$/, '').split('\n').length, dels: 0 }
  return { adds: lines.filter(line => line.startsWith('+')).length, dels: lines.filter(line => line.startsWith('-')).length }
}

export type Call = { tool: string; input: unknown; output?: unknown }

const MENARD_TOOL = /^mcp__plugin_menard_menard__(\w+)$/
const VERBS = 'edit rename find outline clause stmt block attr directive module write deps run map where version'
// A shell command is menard's when menard is what it runs, after a cd at most: one that names
// menard further in (a script, a quoted prompt, a commit message) is a shell command.
const MENARD_SHELL = new RegExp(`^\\s*(?:cd\\s+\\S+\\s*&&\\s*)?(?:\\S*/)?menard\\s+(?:--frozen\\s+)?(${VERBS.replaceAll(' ', '|')})\\b([^\\n;&|<>]*)`)
const MAX_SAID = 100

// What a menard call did, in menard's own words: a write's reply carries `did`, a run's `ok`.
// Before the reply, and for a read, it is the verb and what it was pointed at. null: not menard's.
export const menardSaid = ({ tool, input, output }: Call): string | null => {
  const fields = (input ?? {}) as Record<string, unknown>
  const command = tool === 'Bash' && typeof fields.command === 'string' ? fields.command : ''
  const shell = MENARD_SHELL.exec(command)
  const verb = MENARD_TOOL.exec(tool)?.[1] ?? shell?.[1]
  if (!verb) return null
  // and one that printed more after menard's line of JSON went on to do more
  const stdout = shell ? (output as { stdout?: unknown } | undefined)?.stdout : undefined
  if (typeof stdout === 'string' && /^\{.*\}\s*\n\s*\S/.test(stdout.trimStart())) return null
  // the reply is JSON, itself quoted inside the tool's own result
  const reply = (typeof output === 'string' ? output : JSON.stringify(output ?? '')).replace(/\\+"/g, '"')
  const did = /"did":"([^"]*)"/.exec(reply)?.[1]
  if (did) return did.slice(0, MAX_SAID)
  const edits = Array.isArray(fields.edits) ? (fields.edits as { file?: unknown }[]).map(edit => edit.file) : []
  // from the shell, what follows the verb on its line, less a redirect's descriptor (`2>&1`)
  const given = shell ? shell[2]!.replace(/\s\d$/, '').trim().split(/\s+/) : [...edits, ...Object.values(fields).flat()]
  const targets = given.filter((v): v is string => typeof v === 'string' && v.length <= 60 && !v.includes('\n'))
  const ok = /"ok":(true|false)/.exec(reply)?.[1]
  const said = [verb, ...new Set(targets)].join(' ').slice(0, MAX_SAID)
  return ok === undefined ? said : `${said}: ${ok === 'true' ? 'ok' : 'failed'}`
}

// One tool call as a line a model can summarise a turn from: what ran, on what, and how it went.
// Words that start a step no reader asks after, and wrappers whose own name hides what they run.
const QUIET = new Set(['cd', 'sleep', 'echo', 'printf', 'export', 'set', 'true', 'do', 'done', 'then', 'else', 'fi', 'for', 'while', 'if', 'local', 'rm', 'mkdir'])
const WRAPPER = /^(?:mise run cap|mise exec|systemd-run|timeout|env|command|sudo)\b.*?\s--\s+/
const HAS_VERB = new Set(['git', 'mise', 'menard', 'gh', 'nix', 'npm', 'cargo', 'mix', 'claude', 'tmux', 'systemctl', 'docker', 'make'])

// What a shell command runs, a name for each step: `menard edit · git commit · mise run check`.
// Heredoc bodies, quoted text and what a pipe feeds are not steps.
export const steps = (command: string): string[] => {
  const lines: string[] = []
  let until = ''
  for (const line of command.split('\n')) {
    if (until) {
      if (line.trim() === until) until = ''
      continue
    }
    until = /<<-?\s*['"]?(\w+)['"]?/.exec(line)?.[1] ?? ''
    lines.push(line)
  }
  const parts: string[] = []
  let part = ''
  let quote = ''
  let depth = 0
  const text = lines.join('\n')
  for (let i = 0; i < text.length; i++) {
    const c = text[i]!
    if (quote) {
      if (c === quote) quote = ''
    } else if (c === "'" || c === '"') quote = c
    else if (c === '(' || c === '{') depth += 1
    else if (c === ')' || c === '}') depth -= 1
    else if (depth <= 0 && (c === ';' || c === '\n' || ((c === '&' || c === '|') && text[i + 1] === c))) {
      parts.push(part)
      part = ''
      if (c === '&' || c === '|') i += 1
      continue
    }
    part += c
  }
  parts.push(part)
  const own = new Set<string>()
  const names = parts.flatMap(raw => {
    // a wrapper may wrap a wrapper (systemd-run … -- mise run cap -- …)
    const bare = raw.split(/\s\|\s/)[0]!.trim().replace(WRAPPER, '').replace(WRAPPER, '')
    const words = bare.replace(/^(?:\w+=\S*(?:\s+|$))+/, '').split(/\s+/).filter(Boolean)
    const program = words[0]?.split('/').pop() ?? ''
    // a function the command defines for itself is its own plumbing, as are its calls
    if (words[1] === '()' || program.endsWith('()')) {
      own.add(program.replace(/\(\)$/, ''))
      return []
    }
    if (!/^[\w.-]+$/.test(program) || QUIET.has(program) || own.has(program)) return []
    const verbs = HAS_VERB.has(program) ? words.slice(1, program === 'mise' && words[1] === 'run' ? 3 : 2).filter(word => /^[a-z][\w:-]*$/.test(word)) : []
    return [[program, ...verbs].join(' ')]
  })
  return names.filter((name, index) => name !== names[index - 1])
}

const MAX_STEPS = 6

// A line that only says how long something took: the row has the call's own time beside it.
const TIMING = /^\W*(?:finished|done|took|elapsed|real|user|sys|time|worked|\w+ed for)\b.*\d\s?(?:ms|s|m|min)\b|^\W*\d+(?:\.\d+)?\s?(?:ms|s)\W*$/i
const TIMED = /\s*[[(]\d+(?:\.\d+)?\s?m?s[\])]/g

// The last thing a command said that is not its timing, less a time in brackets at its end.
export const lastSaid = (stdout: string): string => {
  const lines = stdout.split('\n').map(line => line.trim()).filter(Boolean)
  return (lines.findLast(line => !TIMING.test(line)) ?? '').replace(TIMED, '')
}

// How long a call took, for a row: nothing under a second.
export const took = (ms: number | undefined): string => {
  if (ms === undefined || ms < 1000) return ''
  const seconds = Math.round(ms / 1000)
  return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${seconds % 60}s`
}

// a call's line fits one row of a transcript: what was run, then how it ended
const MAX_MADE = 44
const MAX_LAST = 28

// an absolute path is told apart by its file and the folder it is in
const nearby = (text: string) => (text.startsWith('/') && !text.includes(' ') ? text.split('/').slice(-2).join('/') : text)

export const turnLine = (call: Call, isError: boolean): string => {
  const fields = (call.input ?? {}) as Record<string, unknown>
  const failed = isError ? ' (failed)' : ''
  const said = menardSaid(call)
  if (said !== null) return `menard ${said}${failed}`
  if (typeof fields.file_path === 'string' && (call.tool === 'Edit' || call.tool === 'Write')) {
    const { adds, dels } = patchCounts(call.output)
    return `${call.tool} ${nearby(fields.file_path)} +${adds} -${dels}${failed}`
  }
  const first = Object.values(fields).find((v): v is string => typeof v === 'string' && v !== call.tool) ?? ''
  // a command's last line is where it says how it went
  const stdout = call.tool === 'Bash' ? (call.output as { stdout?: unknown } | undefined)?.stdout : undefined
  const last = typeof stdout === 'string' ? lastSaid(stdout).slice(0, MAX_LAST) : ''
  // the steps are joined by dots and the last line may hold some: the files get a mark of their own
  const files = call.tool === 'Bash' ? shellEdits(call.output).map(({ name, adds, dels }) => `${name} +${adds} -${dels}`) : []
  const edited = files.length > 0 ? `  ✎ ${files.join(', ')}` : ''
  // a command of several steps is named by them, one of a single step by its own text
  const ran = call.tool === 'Bash' ? steps(first) : []
  const made = ran.length > 1 ? `${ran.slice(0, MAX_STEPS).join(' · ')}${ran.length > MAX_STEPS ? ` · +${ran.length - MAX_STEPS}` : ''}` : nearby(first.split('\n')[0]!).slice(0, MAX_MADE)
  return `${call.tool} ${made}${failed}${last ? ` → ${last}` : ''}${edited}`.trim()
}

const MAX_CALL_LINES = 30

const cut = (text: string): string[] => {
  const all = text.replace(/\n+$/, '').split('\n')
  return all.length > MAX_CALL_LINES ? [...all.slice(0, MAX_CALL_LINES), `… +${all.length - MAX_CALL_LINES} lines`] : all
}

const replyText = (output: unknown): string => {
  if (typeof output === 'string') return output
  if (Array.isArray(output)) return output.map(block => (typeof block?.text === 'string' ? block.text : JSON.stringify(block))).join('\n')
  const shell = output as { stdout?: unknown; stderr?: unknown } | null
  if (typeof shell?.stdout === 'string') return [shell.stdout, typeof shell.stderr === 'string' ? shell.stderr : ''].filter(Boolean).join('\n')
  return output === undefined ? '' : JSON.stringify(output, null, 2)
}

// A call as it was made and answered, for a line clicked open: the command or the tool's
// arguments, then the reply, each cut to a screen's worth.
export const callText = ({ input, output }: Call): string[] => {
  const fields = (input ?? {}) as Record<string, unknown>
  // an edit is its path and the lines it changed
  const patch = (output as { structuredPatch?: { lines: string[] }[] } | undefined)?.structuredPatch
  if (typeof fields.file_path === 'string' && Array.isArray(patch) && patch.length > 0) return [fields.file_path, ...cut(patch.flatMap(hunk => hunk.lines).join('\n'))]
  const made = typeof fields.command === 'string' ? `$ ${fields.command}` : JSON.stringify(input ?? {}, null, 2)
  const reply = replyText(output)
  return reply === '' ? cut(made) : [...cut(made), ...cut(reply)]
}

type ShellEdits = { bashEditDiff?: { files?: { filePath: string; hunks: { lines: string[] }[] }[] } }

// The files a shell command changed, as its result lists them, each with its counts.
export const shellEdits = (output: unknown): { name: string; adds: number; dels: number }[] =>
  ((output ?? {}) as ShellEdits).bashEditDiff?.files?.map(({ filePath, hunks }) => ({
    name: filePath.split('/').pop() ?? filePath,
    ...patchCounts({ structuredPatch: hunks }),
  })) ?? []

// `git show` with the message first: what the person reads, and each file's own diff. A session
// link in a trailer is a click waiting to happen, so those lines are left out.
export const parseShow = (show: string): { message: string[]; files: Map<string, string> } => {
  const at = show.search(/^diff --git /m)
  const head = at < 0 ? show : show.slice(0, at)
  return {
    message: head.replace(/\n+$/, '').split('\n').filter(line => !/^Claude-Session:/i.test(line)),
    files: at < 0 ? new Map() : splitDiff(show.slice(at)),
  }
}

export const splitDiff = (diff: string): Map<string, string> => {
  const byPath = new Map<string, string>()
  for (const chunk of diff.split(/^(?=diff --git )/m)) {
    // A binary, mode-only or empty file has no ---/+++ lines, and --no-renames keeps both header names equal.
    const name = /^\+\+\+ b\/(.*)$/m.exec(chunk)?.[1] ?? /^--- a\/(.*)$/m.exec(chunk)?.[1] ?? /^diff --git a\/(.*) b\/\1$/m.exec(chunk)?.[1]
    if (name) byPath.set(name.replace(/\t$/, ''), chunk)
  }
  return byPath
}

export const parseDiff = (diff: string): DiffLine[] => {
  const lines: DiffLine[] = []
  let hunk = -1
  for (const text of diff.split('\n')) {
    if (text.startsWith('@@ ')) hunk++
    else if (hunk >= 0 && /^[ +-]/.test(text)) lines.push({ text, hunk })
  }
  return lines
}

export const emptyDiffNote = (text: string) =>
  /^Binary files /m.test(text) ? 'binary file, no text to show'
  : /^old mode /m.test(text) ? 'file mode change only'
  : /^(new|deleted) file mode /m.test(text) ? 'empty file'
  : 'no diff to show'

export const countDiff = (lines: DiffLine[]) => ({
  adds: lines.filter(l => l.text[0] === '+').length,
  dels: lines.filter(l => l.text[0] === '-').length,
})

// delta draws one row per diff line and one blank row between hunks.
export const firstChangedRow = (before: DiffLine[], after: DiffLine[]) => {
  let i = 0
  while (i < after.length && before[i]?.text === after[i]!.text) i++
  const line = after[Math.min(i, after.length - 1)]
  return line ? Math.min(i, after.length - 1) + line.hunk : 0
}

// The engine refuses a whole view over one control character, and any file or filename can hold one.
export const printable = (text: string) => text.replace(/[\x00-\x1f\x7f-\x9f]/g, '·')

// The tail is what tells two paths apart.
export const tailPath = (path: string, width: number) =>
  path.length <= width ? path : `…${path.slice(path.length - Math.max(0, width - 1))}`

export const clamp = (n: number, low: number, high: number) => Math.max(low, Math.min(n, Math.max(low, high)))

// The list's window moves only as far as it takes to show the selection.
export const revealTop = (top: number, selected: number, count: number, rows: number) =>
  clamp(selected < top ? selected : selected >= top + rows ? selected - rows + 1 : top, 0, count - rows)

const ANSI = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']

const hex = (r: number, g: number, b: number) =>
  '#' + [r, g, b].map(n => n.toString(16).padStart(2, '0')).join('')

const color256 = (n: number): string => {
  if (n < 8) return ANSI[n]!
  if (n < 16) return `${ANSI[n - 8]}Bright`
  if (n >= 232) {
    const v = 8 + (n - 232) * 10
    return hex(v, v, v)
  }
  const i = n - 16
  const level = (d: number) => (d === 0 ? 0 : 55 + d * 40)
  return hex(level(Math.floor(i / 36)), level(Math.floor(i / 6) % 6), level(i % 6))
}

type Style = Omit<Run, 't'>

const applySgr = (style: Style, params: number[]): Style => {
  let s = style
  for (let i = 0; i < params.length; i++) {
    const p = params[i] ?? 0
    if (p === 0) s = {}
    else if (p === 1) s = { ...s, bold: true }
    else if (p === 2) s = { ...s, dim: true }
    else if (p === 3) s = { ...s, it: true }
    else if (p === 4) s = { ...s, u: true }
    else if (p === 22) { const { bold, dim, ...rest } = s; s = rest }
    else if (p === 23) { const { it, ...rest } = s; s = rest }
    else if (p === 24) { const { u, ...rest } = s; s = rest }
    else if (p >= 30 && p <= 37) s = { ...s, c: color256(p - 30) }
    else if (p >= 40 && p <= 47) s = { ...s, b: color256(p - 40) }
    else if (p >= 90 && p <= 97) s = { ...s, c: color256(p - 90 + 8) }
    else if (p >= 100 && p <= 107) s = { ...s, b: color256(p - 100 + 8) }
    else if (p === 39) { const { c, ...rest } = s; s = rest }
    else if (p === 49) { const { b, ...rest } = s; s = rest }
    else if (p === 38 || p === 48) {
      const key = p === 38 ? 'c' : 'b'
      if (params[i + 1] === 5) {
        s = { ...s, [key]: color256(params[i + 2] ?? 0) }
        i += 2
      } else if (params[i + 1] === 2) {
        s = { ...s, [key]: hex(params[i + 2] ?? 0, params[i + 3] ?? 0, params[i + 4] ?? 0) }
        i += 4
      }
    }
  }
  return s
}

const pushText = (runs: Run[], style: Style, text: string) => {
  if (text === '') return
  const last = runs[runs.length - 1]
  if (last && JSON.stringify({ ...last, t: '' }) === JSON.stringify({ ...style, t: '' })) last.t += text
  else runs.push({ ...style, t: text })
}

// delta paints a changed line's background to the edge with an erase, which a Text cannot, so it becomes spaces.
export const parseAnsi = (ansi: string, width: number): Run[][] =>
  ansi.replace(/\n$/, '').split('\n').map(line => {
    const runs: Run[] = []
    let style: Style = {}
    let col = 0
    for (const part of line.split(/(\x1b\[[0-9;:]*[A-Za-z])/)) {
      const sgr = /^\x1b\[([0-9;:]*)m$/.exec(part)
      if (sgr) style = applySgr(style, (sgr[1] ?? '').split(/[;:]/).map(n => Number(n) || 0))
      else if (/^\x1b\[0?K$/.test(part)) {
        pushText(runs, style, ' '.repeat(Math.max(0, width - col)))
        col = width
      } else if (!part.startsWith('\x1b[')) {
        pushText(runs, style, printable(part))
        col += [...part].length
      }
    }
    return runs
  })

const MIN_WRAPPED_TEXT = 8
// How far back a row looks for a space to break at before it cuts the word.
const MAX_WORD = 24

// delta draws one row per diff line. A longer one continues on rows of its own, under its text and
// past the line numbers; `starts` is where each delta row landed.
export const wrapRows = (rows: Run[][], width: number): { rows: Run[][]; starts: number[] } => {
  const wrapped: Run[][] = []
  const starts: number[] = []
  for (const row of rows) {
    starts.push(wrapped.length)
    const text = row.map(r => r.t).join('')
    const gutter = [...text.slice(0, text.lastIndexOf('│', 24) + 1)].length
    if ([...text].length <= width || width - gutter < MIN_WRAPPED_TEXT) {
      wrapped.push(row)
      continue
    }
    const cells = row.flatMap(run => [...run.t].map(ch => ({ ch, run })))
    for (let start = 0; start < cells.length; ) {
      const room = start === 0 ? width : width - gutter
      let end = Math.min(cells.length, start + room)
      if (end < cells.length && cells[end]!.ch !== ' ') {
        // never back into the line numbers, whose padding is spaces too
        const low = Math.max(start, start === 0 ? gutter : 0, end - MAX_WORD)
        const space = cells.slice(low, end).map(c => c.ch).lastIndexOf(' ')
        if (space >= 0) end = low + space + 1
      }
      const line: Run[] = start > 0 && gutter ? [{ t: ' '.repeat(gutter) }] : []
      let from = start
      for (let i = start + 1; i <= end; i++) {
        if (i < end && cells[i]!.run === cells[from]!.run) continue
        line.push({ ...cells[from]!.run, t: cells.slice(from, i).map(c => c.ch).join('') })
        from = i
      }
      const fill = cells[end - 1]!.run.b
      if (fill && end - start < room) line.push({ b: fill, t: ' '.repeat(room - (end - start)) })
      wrapped.push(line)
      // the space a row broke before would only indent the next one
      start = cells[end]?.ch === ' ' ? end + 1 : end
    }
  }
  return { rows: wrapped, starts }
}

// A Client's props past 100000 characters unmount it, so an oversized view loses its styling instead.
const VIEW_LIMIT = 80_000

export const fitRows = (rows: Run[][]): Run[][] =>
  JSON.stringify(rows).length <= VIEW_LIMIT ? rows : rows.map(row => [{ t: row.map(r => r.t).join('') }])
