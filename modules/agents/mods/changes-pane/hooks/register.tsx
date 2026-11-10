import type { Register } from 'claude-code'

import { clamp, countDiff, emptyDiffNote, firstChangedRow, fitRows, parseAnsi, parseDiff, parseLog, parseStatus, printable, revealTop, splitDiff, tailPath, wrapRows } from './changes'
import type { Commit, DiffLine, File, Run } from './changes'
import type { Input } from './view'

const PANE = 'changes'
// Without this, /diff draws the built-in panel beside this one.
const BUILT_IN = 'diff'
const POLL_MS = 2000
const MAX_LIST_ROWS = 10
const MAX_COMMITS = 30
// A commit never changes, so its diff is read once; the cap keeps a long session's memory flat.
const MAX_KEPT_COMMITS = 50
const COMMIT = 'commit:'
// Each untracked file costs a process on every poll; an unignored build folder must not cost thousands.
const MAX_UNTRACKED_DIFFS = 30
const CONTEXT_ROWS = 3
const HINT = 'Esc to prompt · j/k select · J/K scroll · wheel scrolls what it is over · L lazygit · prompt to follow'
const OPEN = { id: PANE, title: 'Changes' }

type Diff = { text: string; lines: DiffLine[]; adds: number; dels: number }
// A head names a section of the list and cannot be selected.
type Item = { id: string; kind: 'file' | 'commit' | 'head'; label: string }

// A file's diff needs no file header, the title names it; a commit's several files do.
const deltaArgv = (columns: number, isCommit: boolean) => [
  'delta', '--no-gitconfig', '--dark', '--true-color=always', `--width=${columns}`, '--line-fill-method=spaces',
  '--wrap-max-lines=0', '--paging=never', '--line-numbers',
  ...(isCommit ? [] : ['--file-style=omit', '--file-decoration-style=omit']),
  '--hunk-header-style=omit', '--hunk-header-decoration-style=omit',
  '--minus-style=syntax #3f0001', '--plus-style=syntax #002800',
]

export const register: Register = on => {
  let size = { columns: 0, rows: 0 }
  let files: File[] = []
  let diffs = new Map<string, Diff>()
  let commits: Commit[] = []
  const shown = new Map<string, Diff>()
  let starts: number[] = []
  let listTop = 0
  let hasBaseline = false
  let note = ''
  let selected = ''
  let rows: Run[][] = []
  let renderedKey = ''
  let offset = 0
  let acked = 0
  let isOpen = false
  let isFollowing = true
  let canDraw = false
  let isDismissed = false

  let isRefreshing = false
  let isStale = false
  let refresh: () => Promise<void> = async () => {}

  const items = (): Item[] => [
    ...(files.length > 0
      ? files.map((f): Item => ({ id: f.path, kind: 'file', label: printable(f.path) }))
      : [{ id: '', kind: 'head', label: note || 'nothing uncommitted' } as Item]),
    ...(commits.length > 0
      ? [{ id: '', kind: 'head', label: 'commits' } as Item, ...commits.map((c): Item => ({ id: COMMIT + c.sha, kind: 'commit', label: `${c.sha} ${printable(c.subject)}` }))]
      : []),
  ]
  const selectedIndex = () => {
    const all = items()
    const at = all.findIndex(i => i.kind !== 'head' && i.id === selected)
    return at >= 0 ? at : Math.max(0, all.findIndex(i => i.kind !== 'head'))
  }
  const diffOf = (id: string) => (id.startsWith(COMMIT) ? shown.get(id.slice(COMMIT.length)) : diffs.get(id))
  const listRows = () => clamp(items().length, 1, Math.min(MAX_LIST_ROWS, Math.floor(size.rows / 3)))
  const reveal = () => { listTop = revealTop(listTop, selectedIndex(), items().length, listRows()) }
  // Title, divider and hint take one row each.
  const diffRows = () => Math.max(1, size.rows - listRows() - 3)
  const scrollTo = (next: number) => { offset = clamp(next, 0, rows.length - diffRows()) }
  // A reopen reuses the engine's cached drawing, so no ui.render fires to say the pane is back.
  const seated = ({ isPlaced }: { isPlaced: boolean }) => {
    if (!isPlaced) return
    isOpen = true
    void refresh()
  }

  const viewProps = () => {
    const all = items()
    const firstFile = clamp(listTop, 0, all.length - listRows())
    const current = all[selectedIndex()]
    const diff = diffOf(current?.id ?? '')
    return {
      title: current?.kind === 'file' ? printable(current.id.split('/').pop() ?? '') : current?.kind === 'commit' ? current.label : '',
      isFollowing,
      rows: fitRows(rows.slice(offset, offset + diffRows())),
      diffRows: diffRows(),
      note: files.length === 0 && commits.length === 0 ? note : current?.kind === 'file' && diff?.lines.length === 0 ? emptyDiffNote(diff.text) : '',
      divider: '─'.repeat(Math.max(0, size.columns)),
      files: all.slice(firstFile, firstFile + listRows()).map((item, i) => {
        const diff = diffOf(item.id)
        const adds = diff?.adds ? ` +${diff.adds}` : ''
        const dels = diff?.dels ? ` -${diff.dels}` : ''
        const width = Math.max(1, size.columns - adds.length - dels.length)
        const label = item.kind === 'file' ? tailPath(item.label, width) : item.label.slice(0, width)
        return { label: label.padEnd(width), adds, dels, isSelected: item.kind !== 'head' && firstFile + i === selectedIndex(), isHead: item.kind === 'head' }
      }),
      firstFile,
      hint: HINT,
      acked,
    }
  }

  on('session.start', async ($, e, next) => {
    // status and diff name files from the repo root, whichever folder the session is in.
    const readDiffs = async (listed: File[]) => {
      const root = (await $.process.run(['git', 'rev-parse', '--show-toplevel'])).stdout.trim()
      const tracked = await $.process.run(['git', '--no-optional-locks', '-c', 'core.quotePath=false', 'diff', 'HEAD', '--no-renames', '--no-color', '--no-ext-diff'])
      const texts = splitDiff(tracked.stdout)
      for (const file of listed.filter(f => f.isUntracked).slice(0, MAX_UNTRACKED_DIFFS)) {
        const untracked = await $.process.run(['git', 'diff', '--no-index', '--no-color', '--no-ext-diff', '--', '/dev/null', file.path], { cwd: root })
        texts.set(file.path, untracked.stdout)
      }
      return texts
    }

    const readCommit = async (sha: string) => {
      const show = await $.process.run(['git', '--no-optional-locks', '-c', 'core.quotePath=false', 'show', '--no-color', '--no-ext-diff', '--format=%an · %ar%n%n%B', sha])
      const lines = parseDiff(show.stdout)
      if (shown.size >= MAX_KEPT_COMMITS) shown.clear()
      shown.set(sha, { text: show.stdout, lines, ...countDiff(lines) })
    }

    const load = async () => {
      let jump: number | null = null
      // Without --no-optional-locks this poll takes the index lock and can fail Claude's own git commands.
      const status = await $.process.run(['git', '--no-optional-locks', 'status', '--porcelain=v1', '-z', '-uall'])
      if (status.exitCode !== 0) {
        files = []
        diffs = new Map()
        commits = []
        note = 'not a git repository'
      } else {
        files = parseStatus(status.stdout)
        note = ''
        const log = await $.process.run(['git', '--no-optional-locks', 'log', '-n', String(MAX_COMMITS), '--format=%h%x09%s'])
        commits = log.exitCode === 0 ? parseLog(log.stdout) : []
        const texts = await readDiffs(files)
        const before = diffs
        diffs = new Map(files.map(({ path }) => {
          const text = texts.get(path) ?? ''
          const old = before.get(path)
          if (old?.text === text) return [path, old]
          const lines = parseDiff(text)
          return [path, { text, lines, ...countDiff(lines) }]
        }))

        const changed = files.filter(({ path }) => before.get(path)?.text !== diffs.get(path)?.text)
        const latest = changed[changed.length - 1]
        const moved = hasBaseline && isFollowing && latest
        if (moved) selected = latest.path
        selected = items()[selectedIndex()]?.id ?? ''
        hasBaseline = true
        if (moved) {
          jump = firstChangedRow(before.get(latest.path)?.lines ?? [], diffs.get(latest.path)?.lines ?? [])
          reveal()
        }
      }

      const isCommit = selected.startsWith(COMMIT)
      if (isCommit && !diffOf(selected)) await readCommit(selected.slice(COMMIT.length))
      const text = diffOf(selected)?.text ?? ''
      const key = `${selected}\0${size.columns}\0${text}`
      if (key === renderedKey) return
      renderedKey = key
      if (isCommit ? text === '' : !diffOf(selected)?.lines.length) {
        rows = []
        starts = []
        return
      }
      const drawn = await $.process.run(deltaArgv(size.columns, isCommit), { stdin: text })
      // delta leads a file's diff with the blank row it puts before every hunk.
      const parsed = parseAnsi(drawn.stdout, size.columns)
      ;({ rows, starts } = wrapRows(isCommit ? parsed : parsed.slice(1), size.columns))
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
          const seen = JSON.stringify([renderedKey, note, files, commits])
          await load()
          scrollTo(offset)
          if (seen !== JSON.stringify([renderedKey, note, files, commits])) $.ui.invalidate('ui.render')
        }
      } catch (error) {
        note = `could not read the changes: ${error instanceof Error ? error.message : String(error)}`
        $.ui.invalidate('ui.render')
      } finally {
        isRefreshing = false
      }
    }

    $.clock.every(POLL_MS, () => { void refresh() })
    // VS Code and mobile have no Client to draw this pane with.
    canDraw = e.surface === 'terminal' || e.surface === 'desktop'
    if (canDraw) await $.command.register({ name: PANE, description: 'Show everything uncommitted and the recent commits, following the latest edit', immediate: true })
    return next(e)
  })

  on('command.run', { command: PANE }, async ($, e) => {
    isDismissed = false
    seated(await $.ui.open(OPEN))
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
    const result = await next(e)
    if (isOpen) void refresh()
    else if (canDraw && !isDismissed) {
      // The tool has already run: a failed look at git must not cost it its result.
      try {
        const status = await $.process.run(['git', '--no-optional-locks', 'status', '--porcelain=v1'])
        if (status.exitCode === 0 && status.stdout !== '') seated(await $.ui.open(OPEN))
      } catch {}
    }
    return result
  })

  on('prompt.submit', async ($, e, next) => {
    if (!isFollowing) {
      isFollowing = true
      $.ui.invalidate('ui.render')
    }
    return next(e)
  })

  on('ui.close', { id: PANE }, async ($, e, next) => {
    const closed = await next(e)
    isOpen = false
    if (e.origin.kind === 'person') isDismissed = true
    return closed
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (e.surface !== 'terminal' && e.surface !== 'desktop') return next(e)
    const { Client } = $.ui.resolve(e)
    const isResized = e.props.bodyColumns !== size.columns
    size = { columns: e.props.bodyColumns, rows: e.props.scroll.bodyRows }

    if (!isOpen || isResized) {
      isOpen = true
      void refresh()
    }
    return <Client key="changes" module="./view.tsx" props={viewProps()} width="100%" />
  })

  // The body never overflows: the view draws its own windows of rows, so the wheel moves the one
  // it is over. Title, diff and divider sit above the list.
  on('ui.scroll', { requestId: PANE }, async ($, e) => {
    if (e.pointer !== undefined && e.pointer.row >= diffRows() + 2) {
      const last = items().length - listRows()
      listTop = clamp(clamp(listTop, 0, last) + e.by, 0, last)
    } else {
      isFollowing = false
      scrollTo(offset + e.by)
    }
    $.ui.invalidate('ui.render')
    return {}
  })

  on('ui.message', { requestId: PANE }, async ($, e) => {
    const { inputs } = e.data as { inputs: Input[] }
    const fresh = inputs.filter(i => i.n > acked)
    if (fresh.length === 0) return {}
    acked = fresh[fresh.length - 1]!.n

    const select = (index: number) => {
      const item = items()[index]
      if (!item || item.kind === 'head' || item.id === selected) return
      selected = item.id
      offset = 0
      reveal()
    }
    // j and k step over a section's head.
    const step = (by: 1 | -1) => {
      const all = items()
      let at = selectedIndex() + by
      while (all[at]?.kind === 'head') at += by
      select(at)
    }

    // Keys that reach stdin together arrive as one event, a held j among them.
    const typed = fresh.flatMap(({ key, shift, row }): { key?: string; row?: number }[] =>
      row !== undefined ? [{ row }]
      : key && /^[jkJK]+$/.test(key) ? [...key].map(k => ({ key: shift ? k.toUpperCase() : k }))
      : [{ key: shift && key?.length === 1 ? key.toUpperCase() : key ?? '' }])

    for (const { key, row } of typed) {
      if (key === 'L') {
        const cwd = `--working-directory=${await $.session.cwd()}`
        // setsid -f returns at once and leaves a window that outlives this session.
        try {
          await $.process.run(['setsid', '-f', 'ghostty', cwd, '-e', 'lazygit'])
        } catch {
          // macOS has neither setsid nor ghostty on PATH, and the window open starts may lack Homebrew's PATH.
          const lazygit = (await $.process.run(['which', 'lazygit'])).stdout.trim() || 'lazygit'
          await $.process.run(['open', '-na', 'Ghostty.app', '--args', cwd, '-e', lazygit])
        }
        continue
      }
      if (row !== undefined) select(row)
      else if (key === 'j' || key === 'down') step(1)
      else if (key === 'k' || key === 'up') step(-1)
      else if (key === 'J') scrollTo(offset + 1)
      else if (key === 'K') scrollTo(offset - 1)
      else if (key === 'pagedown') scrollTo(offset + diffRows())
      else if (key === 'pageup') scrollTo(offset - diffRows())
      else continue
      isFollowing = false
    }

    void refresh()
    return { props: viewProps() }
  })
}
