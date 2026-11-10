import type { Register } from 'claude-code'

import { clamp, countDiff, emptyDiffNote, firstChangedRow, fitRows, parseAnsi, parseDiff, parseLog, parseShow, parseStatus, printable, revealTop, splitDiff, tailPath, wrapRows } from './changes'
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
const HINT = 'Esc to prompt · Tab files/commits · j/k select · J/K scroll · L lazygit · prompt to follow'
const OPEN = { id: PANE, title: 'Changes' }

type Diff = { text: string; lines: DiffLine[]; adds: number; dels: number }
type Shown = { message: string[]; diffs: Map<string, Diff> }

const diffOf = (text: string): Diff => {
  const lines = parseDiff(text)
  return { text, lines, ...countDiff(lines) }
}

const deltaArgv = (columns: number) => [
  'delta', '--no-gitconfig', '--dark', '--true-color=always', `--width=${columns}`, '--line-fill-method=spaces',
  '--wrap-max-lines=0', '--paging=never', '--line-numbers',
  '--file-style=omit', '--file-decoration-style=omit', '--hunk-header-style=omit', '--hunk-header-decoration-style=omit',
  '--minus-style=syntax #3f0001', '--plus-style=syntax #002800',
]

export const register: Register = on => {
  let size = { columns: 0, rows: 0 }
  let files: File[] = []
  let diffs = new Map<string, Diff>()
  let commits: Commit[] = []
  let root = ''
  let branch = ''
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

  let isRefreshing = false
  let isStale = false
  let refresh: () => Promise<void> = async () => {}

  const paths = () => (source === '' ? files.map(f => f.path) : [...(shown.get(source)?.diffs.keys() ?? [])])
  const current = () => (source === '' ? diffs.get(file) : shown.get(source)?.diffs.get(file))
  // The working tree leads the commits, so a commit's row is one past its place in the log.
  const commitIndex = () => (source === '' ? 0 : 1 + Math.max(0, commits.findIndex(c => c.sha === source)))
  const fileRows = () => clamp(paths().length, 1, Math.min(MAX_FILE_ROWS, Math.floor(size.rows / 4)))
  const commitRows = () => clamp(commits.length + 1, 1, Math.min(MAX_COMMIT_ROWS, Math.floor(size.rows / 5)))
  // The title, the two section heads and the hint take one row each.
  const diffRows = () => Math.max(1, size.rows - fileRows() - commitRows() - 4)
  const scrollTo = (next: number) => { offset = clamp(next, 0, rows.length - diffRows()) }
  const reveal = () => {
    filesTop = revealTop(filesTop, Math.max(0, paths().indexOf(file)), paths().length, fileRows())
    commitsTop = revealTop(commitsTop, commitIndex(), commits.length + 1, commitRows())
  }
  // A reopen reuses the engine's cached drawing, so no ui.render fires to say the pane is back.
  const seated = ({ isPlaced }: { isPlaced: boolean }) => {
    if (!isPlaced) return
    isOpen = true
    void refresh()
  }

  const row = (label: string, diff: Diff | undefined, isSelected: boolean, tail: boolean) => {
    const adds = diff?.adds ? ` +${diff.adds}` : ''
    const dels = diff?.dels ? ` -${diff.dels}` : ''
    const width = Math.max(1, size.columns - adds.length - dels.length)
    return { label: (tail ? tailPath(label, width) : label.slice(0, width)).padEnd(width), adds, dels, isSelected }
  }

  const viewProps = () => {
    const all = paths()
    const firstFile = clamp(filesTop, 0, all.length - fileRows())
    const firstCommit = clamp(commitsTop, 0, commits.length + 1 - commitRows())
    const commit = commits.find(c => c.sha === source)
    const diff = current()
    const log = [
      { id: '', label: files.length > 0 ? `uncommitted · ${files.length} file${files.length === 1 ? '' : 's'}` : 'uncommitted · nothing' },
      ...commits.map(c => ({ id: c.sha, label: `${c.sha} ${printable(c.subject)}` })),
    ]
    const filesSection: Section = {
      head: commit ? `files in ${commit.sha}` : 'files · uncommitted',
      isFocused: focus === 'files',
      first: firstFile,
      empty: source === '' ? 'nothing uncommitted' : 'no files',
      rows: all.slice(firstFile, firstFile + fileRows()).map(path =>
        row(printable(path), source === '' ? diffs.get(path) : shown.get(source)?.diffs.get(path), path === file, true)),
    }
    const commitsSection: Section = {
      head: ['commits', branch === 'HEAD' ? 'detached' : branch, root.split('/').pop() ?? ''].filter(Boolean).map(printable).join(' · '),
      isFocused: focus === 'commits',
      first: firstCommit,
      empty: '',
      rows: log.slice(firstCommit, firstCommit + commitRows()).map(({ id, label }) => row(label, undefined, id === source, false)),
    }
    return {
      title: file !== '' ? printable(file.split('/').pop() ?? '') : commit ? `${commit.sha} ${printable(commit.subject)}` : '',
      isFollowing,
      rows: fitRows(rows.slice(offset, offset + diffRows())),
      diffRows: diffRows(),
      note: note || (file !== '' && diff?.lines.length === 0 ? emptyDiffNote(diff.text) : ''),
      files: filesSection,
      commits: commitsSection,
      hint: HINT,
      acked,
    }
  }

  on('session.start', async ($, e, next) => {
    // status and diff name files from the repo root, whichever folder the session is in.
    const readDiffs = async (listed: File[]) => {
      const tracked = await $.process.run(['git', '--no-optional-locks', '-c', 'core.quotePath=false', 'diff', 'HEAD', '--no-renames', '--no-color', '--no-ext-diff'])
      const texts = splitDiff(tracked.stdout)
      for (const untracked of listed.filter(f => f.isUntracked).slice(0, MAX_UNTRACKED_DIFFS)) {
        const diff = await $.process.run(['git', 'diff', '--no-index', '--no-color', '--no-ext-diff', '--', '/dev/null', untracked.path], { cwd: root })
        texts.set(untracked.path, diff.stdout)
      }
      return texts
    }

    const readCommit = async (sha: string) => {
      const show = await $.process.run(['git', '--no-optional-locks', '-c', 'core.quotePath=false', 'show', '--no-renames', '--no-color', '--no-ext-diff', '--format=%an · %ar%n%n%B', sha])
      const { message, files: texts } = parseShow(show.stdout)
      if (shown.size >= MAX_KEPT_COMMITS) shown.clear()
      shown.set(sha, { message, diffs: new Map([...texts].map(([path, text]) => [path, diffOf(text)])) })
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
        ;[root = '', branch = ''] = (await $.process.run(['git', 'rev-parse', '--show-toplevel', '--abbrev-ref', 'HEAD'])).stdout.split('\n')
        const log = await $.process.run(['git', '--no-optional-locks', 'log', '-n', String(MAX_COMMITS), '--format=%h%x09%s'])
        commits = log.exitCode === 0 ? parseLog(log.stdout) : []
        const texts = await readDiffs(files)
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
      if (source !== '' && !shown.has(source)) await readCommit(source)
      if (!paths().includes(file)) file = source === '' ? paths()[0] ?? '' : ''
      if (jump !== null) reveal()

      const message = source !== '' && file === '' ? shown.get(source)?.message ?? [] : null
      const text = message ? message.join('\n') : current()?.text ?? ''
      const key = `${source}\0${file}\0${size.columns}\0${text}`
      if (key === renderedKey) return
      renderedKey = key
      if (message) {
        ;({ rows, starts } = wrapRows(message.map(line => [{ t: printable(line) }]), size.columns))
        return
      }
      if (!current()?.lines.length) {
        rows = []
        starts = []
        return
      }
      const drawn = await $.process.run(deltaArgv(size.columns), { stdin: text })
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
    // VS Code and mobile have no Client to draw this pane with.
    canDraw = e.surface === 'terminal' || e.surface === 'desktop'
    if (canDraw) await $.command.register({ name: PANE, description: 'Show what is uncommitted and the recent commits, a file at a time, following the latest edit', immediate: true })
    return next(e)
  })

  on('command.run', { command: PANE }, async $ => {
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

  on('ui.close', { id: PANE }, async (_, e, next) => {
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
  // it is over. The title and the diff sit above the files' head, the commits' head under the files.
  on('ui.scroll', { requestId: PANE }, async ($, e) => {
    const at = e.pointer?.row ?? 0
    if (at >= diffRows() + 2 + fileRows()) {
      const last = commits.length + 1 - commitRows()
      commitsTop = clamp(clamp(commitsTop, 0, last) + e.by, 0, last)
    } else if (at >= diffRows() + 1) {
      const last = paths().length - fileRows()
      filesTop = clamp(clamp(filesTop, 0, last) + e.by, 0, last)
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

    // Keys that reach stdin together arrive as one event, a held j among them.
    const typed = fresh.flatMap(({ key, shift, row, list }): { key?: string; row?: number; list?: List }[] =>
      row !== undefined ? [{ row, list }]
      : key && /^[jkJK]+$/.test(key) ? [...key].map(k => ({ key: shift ? k.toUpperCase() : k }))
      : [{ key: shift && key?.length === 1 ? key.toUpperCase() : key ?? '' }])

    for (const { key, row, list } of typed) {
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
      if (row !== undefined) {
        focus = list ?? 'files'
        if (focus === 'commits') pickCommit(row)
        else pickFile(row)
      } else if (key === 'j' || key === 'down') step(1)
      else if (key === 'k' || key === 'up') step(-1)
      else if (key === 'tab' || key === 'h' || key === 'l' || key === 'left' || key === 'right') focus = focus === 'files' ? 'commits' : 'files'
      else if (key === 'J') scrollTo(offset + 1)
      else if (key === 'K') scrollTo(offset - 1)
      else if (key === 'pagedown') scrollTo(offset + diffRows())
      else if (key === 'pageup') scrollTo(offset - diffRows())
      else continue
      isFollowing = false
      reveal()
    }

    void refresh()
    return { props: viewProps() }
  })
}
