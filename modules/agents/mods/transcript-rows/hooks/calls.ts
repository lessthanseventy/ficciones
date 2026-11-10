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
  // a command that goes on to other steps is a shell command, known before it has printed a thing
  if (shell && steps(command).length > 1) return null
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
  const targets = given.filter((v): v is string => typeof v === 'string' && v !== '-' && v.length <= 60 && !v.includes('\n'))
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
    // a variable set from a command (`n=$(grep …)`) is that command's step
    const words = bare.replace(/^\w+=\$\(/, '').replace(/^(?:\w+=\S*(?:\s+|$))+/, '').split(/\s+/).filter(Boolean)
    const program = words[0]?.split('/').pop() ?? ''
    // a function the command defines for itself is its own plumbing, as are its calls
    if (words[1] === '()' || program.endsWith('()')) {
      own.add(program.replace(/\(\)$/, ''))
      return []
    }
    if (!/^\w[\w.-]*$/.test(program) || QUIET.has(program) || own.has(program)) return []
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
  // colour codes and control characters are not words, and the engine refuses a row that holds one
  const lines = stdout.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '').replace(/[\x00-\x09\x0b-\x1f\x7f-\x9f]/g, ' ').split('\n').map(line => line.trim()).filter(Boolean)
  // a closing bracket or a rule says nothing, and a table's padding is not worth its columns
  return (lines.findLast(line => /[\p{L}\p{N}]/u.test(line) && !TIMING.test(line)) ?? '').replace(TIMED, '').replace(/\s+/g, ' ')
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
  // a command of several steps is named by them, one of a single step by its own text
  const ran = call.tool === 'Bash' ? steps(first) : []
  const made = ran.length > 1 ? `${ran.slice(0, MAX_STEPS).join(' · ')}${ran.length > MAX_STEPS ? ` · +${ran.length - MAX_STEPS}` : ''}` : nearby(first.split('\n')[0]!.replace(/^\s*cd\s+\S+\s*(?:&&|;)\s*/, '')).slice(0, MAX_MADE)
  return `${call.tool} ${made}${failed}${last ? ` → ${last}` : ''}`.trim()
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
