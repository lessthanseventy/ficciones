import type { Register } from 'claude-code'

import { agentRow, describe, feedRow, flashingOf, graph, heartbeat, isInTransit, isMoving, level, modelName, nodeOf, pulsesOf, satelliteRows, sharesOf, turnRow } from './activity'
import type { Agent, Entry, NodeId, Turn } from './activity'

import { clamp, countDiff, deltaArgv, emptyDiffNote, firstChangedRow, fitRows, parseAnsi, parseDiff, parseLog, parseShow, parseStatus, printable, revealTop, splitDiff, tailPath, wrapRows } from './changes'
import type { Commit, DiffLine, File, Run } from './changes'
import type { Input, List, Section } from './view'

const PANE = 'changes'
// Without this, /diff draws the built-in panel beside this one.
const BUILT_IN = 'diff'
const POLL_MS = 2000
const MAX_FILE_ROWS = 8
const MAX_COMMIT_ROWS = 6
const MAX_COMMITS = 30
// A commit never changes, so it is read once; the cap keeps a long session's memory flat.
const MAX_KEPT_COMMITS = 50
// Each untracked file costs a process on every poll; an unignored build folder must not cost thousands.
const MAX_UNTRACKED_DIFFS = 30
const CONTEXT_ROWS = 3
// The pane's keys, each a button under its lists: a hotkey is one lowercase letter.
const KEYS = [['j', 'next'], ['k', 'prev'], ['t', 'list'], ['d', 'down'], ['u', 'up'], ['f', 'follow'], ['l', 'git']] as const

const TABS = [['c', 'changes'], ['a', 'activity']] as const
type Tab = (typeof TABS)[number][1]
const MAX_ENTRIES = 400
const MAX_TURNS = 100
const MIN_LOG_ROWS = 6
// Eight drawings a second while a dot travels, one a second while a call only runs, none at rest:
// a drawing is the whole pane's, and at eight a second through a long call it cost a quarter of a core.
const FRAME_MS = 125
const SLOW_MS = 1000
// Each repository listed costs a git status after every tool call.
const MAX_REPOS = 8
const MIN_GRAPH_ROWS = 13
const MAX_GRAPH_ROWS = 19
const MAX_AGENTS = 30
const MAX_AGENT_ROWS = 4

const OPEN = { id: PANE, title: 'Changes' }
// The tools whose call names the file it writes.
const WRITES = new Set(['Edit', 'Write', 'NotebookEdit'])
type Call = { tool: string; file_path?: unknown; notebook_path?: unknown }

type Diff = { text: string; lines: DiffLine[]; adds: number; dels: number }
type Shown = { message: string[]; diffs: Map<string, Diff> }

const diffOf = (text: string): Diff => {
  const lines = parseDiff(text)
  return { text, lines, ...countDiff(lines) }
}


export const register: Register = on => {
  let size = { columns: 0, rows: 0 }
  let files: File[] = []
  let diffs = new Map<string, Diff>()
  let commits: Commit[] = []
  let ahead = new Set<string>()
  let root = ''
  let branch = ''
  let common = ''
  const shown = new Map<string, Shown>()
  // '' is the working tree; a sha is that commit, and the files list is then the commit's.
  let source = ''
  // '' under a commit is the commit itself: its message.
  let file = ''
  let focus: List = 'files'
  let filesTop = 0
  let commitsTop = 0
  let hasBaseline = false
  let note = ''
  let rows: Run[][] = []
  let starts: number[] = []
  let renderedKey = ''
  let offset = 0
  let acked = 0
  let isOpen = false
  let isFollowing = true
  let canDraw = false
  let isDismissed = false
  // The repository the pane reads, and the git directory its worktrees share.
  let repo = ''
  let shared = ''
  const stamps = new Map<string, string>()
  // The repositories the pane has been on, in the order it came to them, each with its uncommitted files.
  const known = new Map<string, { common: string; dirty: number }>()
  // The row of them, drawn once there are two.
  const repoRows = () => (known.size > 1 ? 1 : 0)
  const listed = () => {
    let room = size.columns + 2
    return [...known]
      .map(([root, { dirty }]) => ({ root, name: root.split('/').pop() ?? '', n: root === repo ? files.length : dirty }))
      .map(({ root, name, n }) => ({ root, label: n > 0 ? `${name} ${n}` : name }))
      .filter(({ label }) => (room -= label.length + 4) >= 0)
  }
  let tab: Tab = 'changes'

  // newest first
  const entries: Entry[] = []
  const counts: Partial<Record<NodeId, number>> = {}
  let feedTop = 0
  // The main loop's turns, newest first, the first of them the one running while `isBusy`.
  let turns: Turn[] = []
  let turnNo = 0
  let frame = 0
  let wake: () => void = () => {}
  // The subagents of the session, newest first; `only` is the one the feed is narrowed to.
  let agents: Agent[] = []
  let only: string | null = null
  // A workflow's agents and the engine's own forks start with no spawn to name them.
  const agentOf = (id: string) => {
    const known = agents.find(a => a.id === id)
    if (known) return known
    const agent: Agent = { id, name: 'agent', model: '', state: 'running', step: 0, doing: '', started: Date.now() }
    agents = [agent, ...agents].slice(0, MAX_AGENTS)
    return agent
  }
  const agentRows = () => Math.min(agents.length, MAX_AGENT_ROWS)
  let model = ''
  let stepNo = 0
  let percent: number | undefined
  let isBusy = false
  let follow: (e: Call) => Promise<boolean> = async () => false
  let sight: () => Promise<void> = async () => {}
  let hold: (root: string) => void = () => {}
  let count: () => Promise<void> = async () => {}

  // A terminal sends one notch of the wheel as a burst of events (Ghostty: three); over a list the
  // burst is one step.
  const NOTCH_MS = 40
  let wheeled = { at: 0, by: 0 }
  // Whether the view has the keyboard. The engine says nothing when a click gives it or Escape
  // takes it back, so it is read from where input lands: here, or in the prompt box.
  let hasKeys = false
  let isRefreshing = false
  let isStale = false
  let refresh: () => Promise<void> = async () => {}

  const paths = () => (source === '' ? files.map(f => f.path) : [...(shown.get(source)?.diffs.keys() ?? [])])
  const current = () => (source === '' ? diffs.get(file) : shown.get(source)?.diffs.get(file))
  // The working tree leads the commits, so a commit's row is one past its place in the log.
  const commitIndex = () => (source === '' ? 0 : 1 + Math.max(0, commits.findIndex(c => c.sha === source)))
  const fileRows = () => clamp(paths().length, 1, Math.min(MAX_FILE_ROWS, Math.floor(size.rows / 4)))
  const commitRows = () => clamp(commits.length + 1, 1, Math.min(MAX_COMMIT_ROWS, Math.floor(size.rows / 5)))
  // The tabs, three boxes' top and bottom edges, and the hint.
  const diffRows = () => Math.max(1, size.rows - fileRows() - commitRows() - 8 - repoRows())
  const scrollTo = (next: number) => { offset = clamp(next, 0, rows.length - diffRows()) }
  const reveal = () => {
    filesTop = revealTop(filesTop, Math.max(0, paths().indexOf(file)), paths().length, fileRows())
    commitsTop = revealTop(commitsTop, commitIndex(), commits.length + 1, commitRows())
  }
  const pickFile = (index: number) => {
    // above a commit's first file is the commit's message
    const path = index < 0 && source !== '' ? '' : paths()[clamp(index, 0, paths().length - 1)]
    if (path === undefined || path === file) return
    file = path
    offset = 0
  }
  const pickCommit = (index: number) => {
    const next = index <= 0 ? '' : commits[Math.min(index, commits.length) - 1]?.sha ?? ''
    if (next === source) return
    source = next
    // the working tree opens on its first file, a commit on its message
    file = ''
    offset = 0
    filesTop = 0
  }
  const step = (by: number) => {
    if (focus === 'commits') pickCommit(commitIndex() + by)
    else pickFile(paths().indexOf(file) + by)
  }
  // A reopen reuses the engine's cached drawing, so no ui.render fires to say the pane is back.
  const seated = ({ isPlaced }: { isPlaced: boolean }) => {
    if (!isPlaced) return
    isOpen = true
    void refresh()
  }

  const row = (lead: string, label: string, diff: Diff | undefined, isSelected: boolean, isPath: boolean) => {
    const adds = diff?.adds ? ` +${diff.adds}` : ''
    const dels = diff?.dels ? ` -${diff.dels}` : ''
    const width = Math.max(1, size.columns - lead.length - adds.length - dels.length)
    const text = (isPath ? tailPath(label, width) : label.slice(0, width)).padEnd(width)
    // a path's folders are drawn dim, so the name is what the eye lands on
    const cut = isPath ? text.lastIndexOf('/') + 1 : 0
    return { lead, dim: text.slice(0, cut), label: text.slice(cut), adds, dels, isSelected }
  }


  const viewProps = () => {
    const all = paths()
    const firstFile = clamp(filesTop, 0, all.length - fileRows())
    const firstCommit = clamp(commitsTop, 0, commits.length + 1 - commitRows())
    const commit = commits.find(c => c.sha === source)
    const diff = current()
    const log = [
      { id: '', lead: '', label: files.length > 0 ? `uncommitted · ${files.length} file${files.length === 1 ? '' : 's'}` : 'uncommitted · nothing' },
      ...commits.map(c => ({ id: c.sha, lead: `${c.sha} `, label: printable(c.subject) })),
    ]
    // a head doubles as the line between two sections
    // A box's top edge holds its title: a corner and a dash before it, the rule after it to the far corner.
    const room = Math.max(0, size.columns - 3)
    const rule = (taken: number) => (room > taken ? ` ${'─'.repeat(room - taken - 1)}` : '')
    const filesHead = (commit ? `files in ${commit.sha}` : 'files · uncommitted').slice(0, room)
    const main = common.endsWith('/.git') ? common.slice(0, -5) : root
    const tree = root.split('/').pop() ?? ''
    const checkout = main === root || main === '' ? tree : `${main.split('/').pop()} ⑂ worktree ${tree}`
    const commitsHead = ['commits', branch === 'HEAD' ? 'detached' : branch, checkout].filter(Boolean).map(printable).join(' · ').slice(0, room)
    // the following mark sits in the edge too, a space each side of it
    const mark = isFollowing ? 13 : 8
    const adds = file !== '' && diff?.adds ? `  +${diff.adds}` : ''
    const dels = file !== '' && diff?.dels ? ` -${diff.dels}` : ''
    const left = Math.max(0, room - mark - adds.length - dels.length)
    const title = (file !== '' ? printable(file.split('/').pop() ?? '') : commit ? `${commit.sha} ${printable(commit.subject)}` : '').slice(0, left)
    const folder = file.includes('/') ? `  ${printable(file.slice(0, file.lastIndexOf('/')))}` : ''
    const where = title.length + folder.length <= left ? folder : ''

    const filesSection: Section = {
      head: filesHead,
      rule: rule(filesHead.length),
      isFocused: hasKeys && focus === 'files',
      first: firstFile,
      empty: source === '' ? 'nothing uncommitted' : 'no files',
      rows: all.slice(firstFile, firstFile + fileRows()).map(path =>
        row('', printable(path), source === '' ? diffs.get(path) : shown.get(source)?.diffs.get(path), path === file, true)),
    }
    const commitsSection: Section = {
      head: commitsHead,
      rule: rule(commitsHead.length),
      isFocused: hasKeys && focus === 'commits',
      first: firstCommit,
      empty: '',
      rows: log.slice(firstCommit, firstCommit + commitRows()).map(({ id, lead, label }) => ({ ...row(lead, label, undefined, id === source, false), isAhead: ahead.has(id) })),
    }
    return {
      title,
      where,
      adds,
      dels,
      // with nothing to title the box, the edge runs unbroken to the mark
      rule: title === '' ? '─'.repeat(Math.max(0, room - mark)) : rule(title.length + where.length + adds.length + dels.length + mark),
      columns: size.columns,
      isFollowing,
      rows: fitRows(rows.slice(offset, offset + diffRows())),
      diffRows: diffRows(),
      note: note || (file !== '' && diff?.lines.length === 0 ? emptyDiffNote(diff.text) : ''),
      files: filesSection,
      commits: commitsSection,

      acked,
    }
  }

  const log = (said: Omit<Entry, 'at' | 'turn'>) => {
    // what is logged already over took no time; what is running has no time yet
    const entry: Entry = { ...said, at: Date.now(), turn: turnNo, ...(said.state === 'running' ? {} : { ms: 0 }) }
    entries.unshift(entry)
    if (entries.length > MAX_ENTRIES) entries.pop()
    counts[entry.node] = (counts[entry.node] ?? 0) + 1
    wake()
    return entry
  }

  const activity = () => {
    const columns = size.columns + 2
    // under the tabs and above the hint
    const room = Math.max(2, size.rows - 2)
    const now = Date.now()
    const band = satelliteRows(agents.length)
    // the head and the heartbeat take a row each
    const graphRows = clamp(room - band - 2 - agentRows() - MIN_LOG_ROWS, MIN_GRAPH_ROWS, MAX_GRAPH_ROWS) + band
    const spent = sharesOf(entries.filter(e => e.turn === turnNo), now)
    const running = new Set(entries.filter(e => e.state === 'running').map(e => e.node))
    if (agents.some(a => a.state === 'running')) running.add('agents')
    const latest = new Map<NodeId, Entry>()
    for (const entry of [...entries].reverse()) latest.set(entry.node, entry)
    const failed = new Set([...latest].filter(([, e]) => e.state === 'failed').map(([node]) => node))
    const centre = [percent === undefined ? '' : `ctx ${Math.round(percent)}%`, 'CLAUDE', model]
    const head: Run[] = model === '' ? [{ t: 'nothing yet this session', dim: true }] : [
      { t: 'Model ', dim: true },
      { t: model, c: 'remember', bold: true },
      { t: ` · step ${stepNo}`, c: 'claude' },
      ...(percent === undefined ? [] : [{ t: ' · context ', dim: true as const }, { t: `${Math.round(percent)}%`, c: level(percent), bold: true as const }]),
    ]
    // the running ones lead, so a finished one is what leaves when there are too many
    const ordered = [...agents.filter(a => a.state === 'running'), ...agents.filter(a => a.state !== 'running')]
    // The log is the turns that have ended and the one running; narrowed to a subagent, it is that one's calls.
    const rows = only === null
      ? turns.map(turn => turnRow(turn.state === 'running' ? { ...turn, shares: spent } : turn, columns, now))
      : entries.filter(e => e.agentId === only).map(entry => feedRow(entry, columns))
    const first = clamp(feedTop, 0, rows.length - 1)
    return {
      top: [
        ...graph(columns, graphRows, {
          // the Agents node counts the subagents, not each step one of them took
          counts: { ...counts, agents: agents.length || undefined },
          running,
          failed,
          flashing: flashingOf(entries, now),
          isOdd: frame % 2 === 1,
          last: entries[0]?.node,
          pulses: pulsesOf(entries, now),
          shares: isBusy ? spent : turns[0]?.shares ?? {},
          agents: ordered,
          centre,
          percent,
          isBusy,
          now,
        }),
        head,
        heartbeat(entries, columns, now),
      ],
      agents: ordered.slice(0, MAX_AGENT_ROWS).map(a => ({ id: a.id, isRunning: a.state === 'running', label: `${a.id === only ? '▶ ' : ''}${agentRow(a, columns - (a.id === only ? 2 : 0), now)}` })),
      feed: rows.slice(first, first + Math.max(0, room - graphRows - 2 - agentRows())),
    }
  }

  on('agent.spawn', async ($, e, next) => {
    const spawned = await next(e)
    if ('agentId' in spawned && spawned.agentId !== undefined) {
      Object.assign(agentOf(spawned.agentId), { name: e.description || e.subagentType, model: modelName(spawned.model) })
      if (isOpen && tab === 'activity') $.ui.invalidate('ui.render')
    }
    return spawned
  })

  on('prompt.submit', async ($, e, next) => {
    // a background agent or shell reporting back is a prompt too, and not the person's
    log(e.origin?.kind === 'task-notification' ? { node: 'agents', text: 'a task reports back', state: 'done' } : { node: 'you', text: 'new message', state: 'done' })
    if (isOpen && tab === 'activity') $.ui.invalidate('ui.render')
    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) {
      isBusy = true
      turnNo += 1
      turns = [{ n: turnNo, started: Date.now(), steps: 0, calls: 0, failed: 0, state: 'running' as const, shares: {} }, ...turns].slice(0, MAX_TURNS)
    } else Object.assign(agentOf(e.agentId), { state: 'running', ms: undefined })
    wake()
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      isBusy = false
      const turn = turns[0]
      if (turn?.state === 'running') {
        const now = Date.now()
        Object.assign(turn, { ms: now - turn.started, state: e.reason === 'answer' ? 'done' : 'failed', shares: sharesOf(entries.filter(entry => entry.turn === turn.n), now) })
      }
    } else {
      const agent = agentOf(e.agentId)
      Object.assign(agent, { state: e.reason === 'answer' ? 'done' : 'failed', ms: Date.now() - agent.started })
    }
    if (isOpen && tab === 'activity') $.ui.invalidate('ui.render')
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    const agent = e.agentId === undefined ? null : agentOf(e.agentId)
    if (agent) Object.assign(agent, { step: e.index + 1, model: agent.model || modelName(e.model), doing: 'thinking', node: 'model' })
    else {
      model = modelName(e.model)
      stepNo = e.index + 1
      if (turns[0]?.state === 'running') turns[0].steps += 1
    }
    const entry = log(agent
      ? { node: 'agents', text: `${agent.model} · step ${agent.step}`, state: 'running', agentId: agent.id, agent: agent.name }
      : { node: 'model', text: `${model} · step ${stepNo}`, state: 'running' })
    const started = Date.now()
    if (isOpen && tab === 'activity') $.ui.invalidate('ui.render')
    try {
      const response = yield* next(e)
      entry.state = 'done'
      return response
    } catch (error) {
      entry.state = 'failed'
      throw error
    } finally {
      entry.ms = Date.now() - started
      if (!agent) {
        // The status line counts the context against the compaction budget where one is set, and so does this.
        const context = (await $.session.usage().catch(() => null))?.context
        const budget = await $.settings.read({ key: 'autoCompactWindow' }).catch(() => undefined)
        percent = typeof budget === 'number' && context?.tokens ? (context.tokens * 100) / budget : context?.percent ?? percent
      }
      if (isOpen && tab === 'activity') $.ui.invalidate('ui.render')
    }
  })

  on('session.start', async ($, e, next) => {
    const where = async (dir: string) => {
      const top = await $.process.run(['git', 'rev-parse', '--show-toplevel', '--path-format=absolute', '--git-common-dir'], { cwd: dir })
      if (top.exitCode !== 0) return null
      const [at = '', shared = ''] = top.stdout.split('\n')
      return { root: at || dir, common: shared }
    }

    // What a shell command can change in a repository: its tree, its commit, the text of its diff.
    const stamp = async (dir: string) => {
      const run = (...args: string[]) => $.process.run(['git', '--no-optional-locks', ...args], { cwd: dir })
      const read = [await run('status', '--porcelain=v1'), await run('rev-parse', 'HEAD'), await run('diff', 'HEAD', '--shortstat')]
      return read.map(r => r.stdout).join('\0')
    }

    const enter = (at: { root: string; common: string }, path = '') => {
      const left = known.get(repo)
      if (left) left.dirty = files.length
      repo = at.root
      shared = at.common
      if (!known.has(repo) && known.size >= MAX_REPOS) known.delete(known.keys().next().value!)
      known.set(repo, known.get(repo) ?? { common: shared, dirty: 0 })
      files = []
      diffs = new Map()
      commits = []
      ahead = new Set()
      shown.clear()
      source = ''
      file = path
      hasBaseline = false
      rows = []
      starts = []
      renderedKey = ''
      offset = 0
      filesTop = 0
      commitsTop = 0
    }

    hold = root => {
      const at = known.get(root)
      if (!at || root === repo) return
      enter({ root, common: at.common })
      isFollowing = false
    }

    count = async () => {
      for (const [root, at] of known) {
        if (root === repo) continue
        const status = await $.process.run(['git', '--no-optional-locks', 'status', '--porcelain=v1', '-uall'], { cwd: root })
        at.dirty = status.stdout.split('\n').filter(Boolean).length
      }
    }

    // Read before a call, so that what the call itself changes in the session's repository shows after it.
    sight = async () => {
      if (!isFollowing || repo === '') return
      const at = await where(await $.session.cwd())
      if (at && at.root !== repo && at.common !== shared) stamps.set(at.root, await stamp(at.root))
    }

    // The pane stays on the repository being worked in: an edit moves it, a cd alone does not.
    follow = async e => {
      if (!isFollowing && repo !== '') return false
      const cwd = await $.session.cwd()
      const edited = WRITES.has(e.tool) ? e.file_path ?? e.notebook_path : undefined
      if (typeof edited === 'string') {
        const path = edited.startsWith('/') ? edited : `${cwd}/${edited}`
        const at = await where(path.slice(0, path.lastIndexOf('/')))
        if (at && at.root !== repo) {
          enter(at, path.startsWith(`${at.root}/`) ? path.slice(at.root.length + 1) : '')
          return true
        }
      }
      const at = await where(cwd)
      if (!at || at.root === repo) return false
      // a worktree of the repository shown is the same work, moved
      if (repo !== '' && at.common !== shared) {
        const now = await stamp(at.root)
        const before = stamps.get(at.root)
        stamps.set(at.root, now)
        if (before === undefined || before === now) return false
      }
      enter(at)
      return true
    }

    // status and diff name files from the repo root, whichever folder the session is in.
    const readDiffs = async (at: string, listed: File[]) => {
      const tracked = await $.process.run(['git', '--no-optional-locks', '-c', 'core.quotePath=false', 'diff', 'HEAD', '--no-renames', '--no-color', '--no-ext-diff'], { cwd: at })
      const texts = splitDiff(tracked.stdout)
      for (const untracked of listed.filter(f => f.isUntracked).slice(0, MAX_UNTRACKED_DIFFS)) {
        const diff = await $.process.run(['git', 'diff', '--no-index', '--no-color', '--no-ext-diff', '--', '/dev/null', untracked.path], { cwd: at })
        texts.set(untracked.path, diff.stdout)
      }
      return texts
    }

    const readCommit = async (at: string, sha: string) => {
      const show = await $.process.run(['git', '--no-optional-locks', '-c', 'core.quotePath=false', 'show', '--no-renames', '--no-color', '--no-ext-diff', '--format=%an · %ar%n%n%B', sha], { cwd: at })
      const { message, files: texts } = parseShow(show.stdout)
      if (at !== repo) return
      if (shown.size >= MAX_KEPT_COMMITS) shown.clear()
      shown.set(sha, { message, diffs: new Map([...texts].map(([path, text]) => [path, diffOf(text)])) })
    }

    const load = async () => {
      let jump: number | null = null
      // A move to another repository while this reads leaves it for the next pass.
      const at = repo
      const git = (...args: string[]) => $.process.run(['git', '--no-optional-locks', ...args], { cwd: at })
      // Without --no-optional-locks this poll takes the index lock and can fail Claude's own git commands.
      const status = at === '' ? null : await git('status', '--porcelain=v1', '-z', '-uall')
      if (!status || status.exitCode !== 0) {
        if (at !== repo) return
        files = []
        diffs = new Map()
        commits = []
        note = 'not a git repository'
      } else {
        const listed = parseStatus(status.stdout)
        // the common git directory sits in the main checkout, which a linked worktree is not
        const names = (await git('rev-parse', '--show-toplevel', '--abbrev-ref', 'HEAD', '--path-format=absolute', '--git-common-dir')).stdout.split('\n')
        const log = await git('log', '-n', String(MAX_COMMITS), '--format=%h%x09%s')
        // a branch with no upstream has nothing to be ahead of
        const unpushed = await git('log', '-n', String(MAX_COMMITS), '--format=%h', '@{upstream}..HEAD')
        const texts = await readDiffs(at, listed)
        if (at !== repo) return
        files = listed
        note = ''
        ;[root = '', branch = '', common = ''] = names
        commits = log.exitCode === 0 ? parseLog(log.stdout) : []
        ahead = new Set(unpushed.exitCode === 0 ? unpushed.stdout.split('\n').filter(Boolean) : [])
        const before = diffs
        diffs = new Map(files.map(({ path }) => {
          const text = texts.get(path) ?? ''
          const old = before.get(path)
          return [path, old?.text === text ? old : diffOf(text)]
        }))

        const changed = files.filter(({ path }) => before.get(path)?.text !== diffs.get(path)?.text)
        const latest = changed[changed.length - 1]
        const moved = hasBaseline && isFollowing && latest
        if (moved) {
          source = ''
          file = latest.path
          jump = firstChangedRow(before.get(latest.path)?.lines ?? [], diffs.get(latest.path)?.lines ?? [])
        }
        hasBaseline = true
      }

      // A commit amended or rebased away leaves the working tree.
      if (source !== '' && !commits.some(c => c.sha === source)) source = ''
      if (source !== '' && !shown.has(source)) await readCommit(at, source)
      if (at !== repo) return
      if (!paths().includes(file)) file = source === '' ? paths()[0] ?? '' : ''
      if (jump !== null) reveal()

      const message = source !== '' && file === '' ? shown.get(source)?.message ?? [] : null
      const text = message ? message.join('\n') : current()?.text ?? ''
      const key = `${source}\0${file}\0${size.columns}\0${text}`
      if (key === renderedKey) return
      renderedKey = key
      if (message) {
        // who and when, then the subject, the body, and the trailers
        const styled = message.map((line, i): Run[] => [{
          t: printable(line),
          ...(i === 0 || /^[A-Z][\w-]+-by: /i.test(line) ? { dim: true as const } : i === 2 ? { bold: true as const } : {}),
        }])
        ;({ rows, starts } = wrapRows(styled, size.columns))
        return
      }
      if (!current()?.lines.length) {
        rows = []
        starts = []
        return
      }
      const drawn = await $.process.run(deltaArgv(size.columns), { stdin: text })
      if (at !== repo) return
      // delta leads with the blank row it puts before every hunk.
      ;({ rows, starts } = wrapRows(parseAnsi(drawn.stdout, size.columns).slice(1), size.columns))
      if (jump !== null) offset = Math.max(0, (starts[jump] ?? 0) - CONTEXT_ROWS)
    }

    refresh = async () => {
      if (!isOpen) return
      isStale = true
      if (isRefreshing) return
      isRefreshing = true
      try {
        while (isStale) {
          isStale = false
          const seen = JSON.stringify([renderedKey, note, files, commits, branch])
          await load()
          scrollTo(offset)
          if (seen !== JSON.stringify([renderedKey, note, files, commits, branch])) $.ui.invalidate('ui.render')
        }
      } catch (error) {
        note = `could not read the changes: ${error instanceof Error ? error.message : String(error)}`
        $.ui.invalidate('ui.render')
      } finally {
        isRefreshing = false
      }
    }

    $.clock.every(POLL_MS, () => { void refresh() })
    let tick: { cancel: () => void } | null = null
    wake = () => {
      if (tick || !isOpen || tab !== 'activity') return
      let drawn = 0
      tick = $.clock.every(FRAME_MS, () => {
        const now = Date.now()
        const isLive = isOpen && tab === 'activity' && isMoving(entries, agents, now)
        if (isLive && !isInTransit(entries, now) && now - drawn < SLOW_MS) return
        drawn = now
        frame += 1
        $.ui.invalidate('ui.render')
        // one drawing after the last thing has come to rest, then none
        if (isLive) return
        tick?.cancel()
        tick = null
      })
    }
    // VS Code and mobile have no Client to draw this pane with.
    canDraw = e.surface === 'terminal' || e.surface === 'desktop'
    if (canDraw) {
      const at = await where(e.cwd).catch(() => null)
      if (at) enter(at)
      await $.command.register({ name: PANE, description: 'Show or hide what is uncommitted and the recent commits, a file at a time, following the latest edit', immediate: true })
      // In a repository the pane is up from the start; a session must still start where it cannot open.
      try {
        if (at) seated(await $.ui.open(OPEN))
      } catch {}
    }
    return next(e)
  })

  on('command.run', { command: PANE }, async $ => {
    isDismissed = isOpen
    if (isOpen) await $.ui.close({ id: PANE })
    else seated(await $.ui.open(OPEN))
    return {}
  })

  on('command.run', { command: BUILT_IN }, async ($, e, next) => {
    if (!canDraw) return next(e)
    isDismissed = false
    seated(await $.ui.open(OPEN))
    return {}
  })


  // The poll alone would leave up to two seconds between an edit and the pane following it.
  on('tool.call', async ($, e, next) => {
    if (canDraw) await sight().catch(() => {})
    const call = e as unknown as { tool: string }
    const agent = e.agentId === undefined ? null : agentOf(e.agentId)
    if (agent) Object.assign(agent, { doing: describe(call), node: nodeOf(call) })
    const turn = !agent && turns[0]?.state === 'running' ? turns[0] : null
    if (turn) turn.calls += 1
    const entry = log({ node: nodeOf(call), text: describe(call), state: 'running', ...(agent ? { agentId: agent.id, agent: agent.name } : {}) })
    const started = Date.now()
    if (isOpen && tab === 'activity') $.ui.invalidate('ui.render')
    const result = await next(e).finally(() => {
      entry.state = 'failed'
      entry.ms = Date.now() - started
    })
    entry.state = 'deny' in result || ('isError' in result && result.isError) ? 'failed' : 'done'
    if (turn && entry.state === 'failed') turn.failed += 1
    if (isOpen && tab === 'activity') $.ui.invalidate('ui.render')
    if (!canDraw) return result
    // The tool has already run: a failed look at git must not cost it its result.
    try {
      const hasMoved = await follow(e as Call)
      await count()
      if (isOpen) void refresh()
      else if (!isDismissed && repo !== '') {
        // A move into a repository opens the pane with nothing uncommitted.
        const status = await $.process.run(['git', '--no-optional-locks', 'status', '--porcelain=v1'], { cwd: repo })
        if (status.exitCode === 0 && (hasMoved || status.stdout !== '')) seated(await $.ui.open(OPEN))
      }
    } catch {}
    return result
  })


  const act = (key: string) => {
    if (key === 'f') {
      isFollowing = !isFollowing
      // following is of the working tree
      if (isFollowing) {
        focus = 'files'
        pickCommit(0)
        reveal()
      }
      return
    }

    if (key === 'j') step(1)
    else if (key === 'k') step(-1)
    else if (key === 't') focus = focus === 'files' ? 'commits' : 'files'
    else if (key === 'd') scrollTo(offset + 1)
    else if (key === 'u') scrollTo(offset - 1)
    isFollowing = false
    reveal()
  }

  on('ui.close', { id: PANE }, async (_, e, next) => {
    const closed = await next(e)
    isOpen = false
    if (e.origin.kind === 'person') isDismissed = true
    return closed
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (e.surface !== 'terminal' && e.surface !== 'desktop') return next(e)
    const { Client, Box, Text, Button } = $.ui.resolve(e)
    if (hasKeys !== e.props.isFocused) {
      hasKeys = e.props.isFocused
      void refresh()
    }
    // a box's edges take a column each side
    const columns = Math.max(1, e.props.bodyColumns - 2)
    const isResized = columns !== size.columns
    size = { columns, rows: e.props.scroll.bodyRows }

    if (!isOpen || isResized) {
      isOpen = true
      void refresh()
    }
    return (
      <Box flexDirection="column">
        <Box>
          {TABS.map(([hotkey, id]) => (
            <Box marginRight={2}>
              {id === tab ? <Text inverse weight="bold" color="claude"> {id} </Text> : (
                <Button
                  plain
                  dimColor={!hasKeys}
                  key={`tab-${id}`}
                  hotkey={hotkey}
                  label={id}
                  onPress={async () => {
                    tab = id
                    wake()
                    $.ui.invalidate('ui.render')
                  }}
                />
              )}
            </Box>
          ))}
        </Box>
        {tab === 'changes' && repoRows() > 0 ? (
          <Box>
            {listed().map(({ root, label }) => (
              <Box marginRight={2}>
                {root === repo ? <Text inverse weight="bold" color="remember"> {label} </Text> : (
                  <Button
                    plain
                    key={`repo-${root}`}
                    label={label}
                    onPress={async () => {
                      hold(root)
                      await refresh()
                      $.ui.invalidate('ui.render')
                    }}
                  />
                )}
              </Box>
            ))}
          </Box>
        ) : null}
        {tab === 'changes' ? <Client key="changes" module="./view.tsx" props={viewProps()} width="100%" /> : (
          (({ top, agents: rows, feed }) => {
            const drawn = (row: Run[]) => (
              <Text wrap="truncate-end">
                {row.map(r => <Text color={r.c} weight={r.bold ? 'bold' : undefined} dimColor={r.dim}>{r.t}</Text>)}
              </Text>
            )
            return (
              <Box flexDirection="column">
                {top.map(drawn)}
                {rows.map(({ id, isRunning, label }) => (
                  <Button
                    plain
                    dimColor={!isRunning}
                    key={`agent-${id}`}
                    label={label}
                    onPress={async () => {
                      only = only === id ? null : id
                      feedTop = 0
                      $.ui.invalidate('ui.render')
                    }}
                  />
                ))}
                {feed.map(drawn)}
              </Box>
            )
          })(activity())
        )}
        <Box>
          {hasKeys ? <Text inverse weight="bold" color="claude"> {tab.toUpperCase()} </Text> : <Text dimColor>○ click</Text>}
          {(tab === 'changes' ? KEYS : []).map(([hotkey, label]) => (
            <Box marginLeft={1}>
              <Button
                plain
                dimColor={!hasKeys}
                key={`key-${hotkey}`}
                hotkey={hotkey}
                label={label}
                onPress={async () => {
                  if (hotkey === 'l') {
                    const cwd = `--working-directory=${repo || await $.session.cwd()}`
                    // setsid -f returns at once and leaves a window that outlives this session.
                    try {
                      await $.process.run(['setsid', '-f', 'ghostty', cwd, '-e', 'lazygit'])
                    } catch {
                      // macOS has neither setsid nor ghostty on PATH, and the window open starts may lack Homebrew's PATH.
                      const lazygit = (await $.process.run(['which', 'lazygit'])).stdout.trim() || 'lazygit'
                      await $.process.run(['open', '-na', 'Ghostty.app', '--args', cwd, '-e', lazygit])
                    }
                    return
                  }
                  act(hotkey)
                  await refresh()
                  // a key that changes no git state (follow, hold) still changes the drawing
                  $.ui.invalidate('ui.render')
                }}
              />
            </Box>
          ))}
        </Box>
      </Box>
    )
  })

  // The body never overflows: the view draws its own windows of rows, so the wheel acts on the one
  // it is over: the diff's box, then the files' box, then the commits'.
  on('ui.scroll', { requestId: PANE }, async ($, e) => {
    if (tab === 'activity') {
      feedTop = clamp(feedTop + e.by, 0, (only === null ? turns : entries.filter(entry => entry.agentId === only)).length - 1)
      $.ui.invalidate('ui.render')
      return {}
    }
    // the tabs take the body's first row, the repositories the one under it
    const at = (e.pointer?.row ?? 0) - 1 - repoRows()
    isFollowing = false
    if (at < diffRows() + 2) scrollTo(offset + e.by)
    else {
      // over a list the wheel walks its selection, which a list that fits can show too
      focus = at >= diffRows() + 4 + fileRows() ? 'commits' : 'files'
      const now = Date.now()
      const by = Math.sign(e.by)
      const isSameNotch = by === wheeled.by && now - wheeled.at < NOTCH_MS
      wheeled = { at: now, by }
      if (isSameNotch) return {}
      step(by)
      reveal()
      void refresh()
    }
    $.ui.invalidate('ui.render')
    return {}
  })

  on('ui.message', { requestId: PANE }, async ($, e) => {
    const { inputs } = e.data as { inputs: Input[] }
    const fresh = inputs.filter(i => i.n > acked)
    if (fresh.length === 0) return {}
    acked = fresh[fresh.length - 1]!.n
    // A click here is the person asking for the pane's keys: with Claude Code's own focus the
    // pane hears when Escape, or a key it does not bind, hands them back.
    await $.ui.open({ ...OPEN, focus: true })

    for (const { row, list } of fresh) {
      if (row === undefined) continue
      focus = list ?? 'files'
      if (focus === 'commits') pickCommit(row)
      else pickFile(row)
      isFollowing = false
      reveal()
    }

    void refresh()
    return { props: viewProps() }
  })
}
