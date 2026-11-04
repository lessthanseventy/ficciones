import type { Register } from 'claude-code'

import { clamp, countDiff, firstChangedRow, fitRows, listStart, parseAnsi, parseDiff, parseStatus, splitDiff, tailPath } from './changes'
import type { DiffLine, File, Run } from './changes'
import type { Input } from './view'

const PANE = 'changes'
// Without this, /diff draws the built-in panel beside this one.
const BUILT_IN = 'diff'
const POLL_MS = 2000
const MAX_LIST_ROWS = 8
// Each untracked file costs a process on every poll; an unignored build folder must not cost thousands.
const MAX_UNTRACKED_DIFFS = 30
const CONTEXT_ROWS = 3
const HINT = 'click to hold · j/k file · J/K scroll · L lazygit · send a prompt to follow'

type Diff = { text: string; lines: DiffLine[]; adds: number; dels: number }

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

  const selectedIndex = () => Math.max(0, files.findIndex(f => f.path === selected))
  const listRows = () => clamp(files.length, 1, Math.min(MAX_LIST_ROWS, Math.floor(size.rows / 3)))
  // Title, divider and hint take one row each.
  const diffRows = () => Math.max(1, size.rows - listRows() - 3)
  const scrollTo = (next: number) => { offset = clamp(next, 0, rows.length - diffRows()) }

  const viewProps = () => {
    const firstFile = listStart(selectedIndex(), files.length, listRows())
    const path = files[selectedIndex()]?.path ?? ''
    return {
      title: path.split('/').pop() ?? '',
      isFollowing,
      rows: fitRows(rows.slice(offset, offset + diffRows())),
      diffRows: diffRows(),
      note,
      divider: '─'.repeat(Math.max(0, size.columns)),
      files: files.slice(firstFile, firstFile + listRows()).map((file, i) => {
        const diff = diffs.get(file.path)
        const adds = diff?.adds ? ` +${diff.adds}` : ''
        const dels = diff?.dels ? ` -${diff.dels}` : ''
        const width = Math.max(1, size.columns - adds.length - dels.length)
        return { label: tailPath(file.path, width).padEnd(width), adds, dels, isSelected: firstFile + i === selectedIndex() }
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

    const load = async () => {
      // Without --no-optional-locks this poll takes the index lock and can fail Claude's own git commands.
      const status = await $.process.run(['git', '--no-optional-locks', 'status', '--porcelain=v1', '-z', '-uall'])
      if (status.exitCode !== 0) {
        files = []
        diffs = new Map()
        note = 'not a git repository'
      } else {
        files = parseStatus(status.stdout)
        note = files.length === 0 ? 'nothing changed' : ''
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
        selected = files[selectedIndex()]?.path ?? ''
        hasBaseline = true
        if (moved) offset = Math.max(0, firstChangedRow(before.get(latest.path)?.lines ?? [], diffs.get(latest.path)?.lines ?? []) - CONTEXT_ROWS)
      }

      const text = diffs.get(selected)?.text ?? ''
      const key = `${selected}\0${size.columns}\0${text}`
      if (key === renderedKey) return
      renderedKey = key
      if (text === '') {
        rows = []
        return
      }
      const drawn = await $.process.run(deltaArgv(size.columns), { stdin: text })
      // delta leads with the blank row it puts before every hunk.
      rows = parseAnsi(drawn.stdout, size.columns).slice(1)
    }

    refresh = async () => {
      if (!isOpen) return
      isStale = true
      if (isRefreshing) return
      isRefreshing = true
      try {
        while (isStale) {
          isStale = false
          const seen = JSON.stringify([renderedKey, note, files])
          await load()
          scrollTo(offset)
          if (seen !== JSON.stringify([renderedKey, note, files])) $.ui.invalidate('ui.render')
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
    if (canDraw) await $.command.register({ name: PANE, description: 'Show everything uncommitted, following the latest edit', immediate: true })
    return next(e)
  })

  on('command.run', { command: PANE }, async ($, e) => {
    isDismissed = false
    await $.ui.open({ id: PANE, title: 'Changes' })
    return {}
  })

  on('command.run', { command: BUILT_IN }, async ($, e, next) => {
    if (!canDraw) return next(e)
    isDismissed = false
    await $.ui.open({ id: PANE, title: 'Changes' })
    return {}
  })


  // The poll alone would leave up to two seconds between an edit and the pane following it.
  on('tool.call', async ($, e, next) => {
    const result = await next(e)
    if (isOpen) void refresh()
    else if (canDraw && !isDismissed) {
      const status = await $.process.run(['git', '--no-optional-locks', 'status', '--porcelain=v1'])
      if (status.exitCode === 0 && status.stdout !== '') await $.ui.open({ id: PANE, title: 'Changes' })
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

  on('ui.message', { requestId: PANE }, async ($, e) => {
    const { inputs } = e.data as { inputs: Input[] }
    const fresh = inputs.filter(i => i.n > acked)
    if (fresh.length === 0) return {}
    acked = fresh[fresh.length - 1]!.n
    isFollowing = false

    const select = (index: number) => {
      const file = files[clamp(index, 0, files.length - 1)]
      if (!file || file.path === selected) return
      selected = file.path
      offset = 0
    }

    // Keys that reach stdin together arrive as one event, a held j among them.
    const typed = fresh.flatMap(({ key, shift, row }): { key?: string; row?: number }[] =>
      row !== undefined ? [{ row }]
      : key && /^[jkJK]+$/.test(key) ? [...key].map(k => ({ key: shift ? k.toUpperCase() : k }))
      : [{ key: shift && key?.length === 1 ? key.toUpperCase() : key ?? '' }])

    for (const { key, row } of typed) {
      if (row !== undefined) select(row)
      else if (key === 'j' || key === 'down') select(selectedIndex() + 1)
      else if (key === 'k' || key === 'up') select(selectedIndex() - 1)
      else if (key === 'J') scrollTo(offset + 1)
      else if (key === 'K') scrollTo(offset - 1)
      else if (key === 'pagedown') scrollTo(offset + diffRows())
      else if (key === 'pageup') scrollTo(offset - diffRows())
      else if (key === 'L') {
        // setsid -f returns at once and leaves a window that outlives this session.
        await $.process.run(['setsid', '-f', 'ghostty', `--working-directory=${await $.session.cwd()}`, '-e', 'lazygit'])
      }
    }

    void refresh()
    return { props: viewProps() }
  })
}
