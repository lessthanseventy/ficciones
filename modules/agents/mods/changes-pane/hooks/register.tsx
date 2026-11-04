import type { Register } from 'claude-code'

import { clamp, countDiff, isFullyStaged, lastOffset, listStart, parseDiff, parseStatus, tailPath, windowDiff } from './changes'
import type { DiffLine, File } from './changes'
import type { Input } from './view'

// The id the bundled diff panel opens its pane under. Drawing it from here keeps
// that plugin's auto-open, /diff and close behaviour and replaces only the body.
const PANE = 'diff'
const POLL_MS = 2000
const MAX_LIST_ROWS = 8
const HINT = 'click for keys · j/k file · J/K scroll · space stage · L lazygit'

export const register: Register = on => {
  let size = { columns: 0, rows: 0 }
  let branch = ''
  let files: File[] = []
  let note = ''
  let selected = ''
  let lines: DiffLine[] = []
  let offset = 0
  let acked = 0
  let isOpen = false
  let isRefreshing = false
  let isStale = false
  let lastSeen = ''
  let refresh: () => Promise<void> = async () => {}

  const selectedIndex = () => Math.max(0, files.findIndex(f => f.path === selected))

  const listRows = () => clamp(files.length, 1, Math.min(MAX_LIST_ROWS, Math.floor(size.rows / 3)))
  // Header, title and hint take one row each.
  const diffRows = () => Math.max(1, size.rows - listRows() - 3)
  const scrollTo = (next: number) => { offset = clamp(next, 0, lastOffset(lines, diffRows())) }

  const viewProps = () => {
    const firstRow = listStart(selectedIndex(), files.length, listRows())
    const path = files[selectedIndex()]?.path ?? ''
    const { adds, dels } = countDiff(lines)
    const stats = `${path.split('/').pop()}  +${adds} -${dels}`
    const labelWidth = Math.max(1, size.columns - 3)
    return {
      branch,
      rows: files.slice(firstRow, firstRow + listRows()).map((file, i) => ({
        file,
        label: tailPath(file.path, labelWidth).padEnd(labelWidth),
        isSelected: firstRow + i === selectedIndex(),
      })),
      firstRow,
      title: path ? `${stats} ${'─'.repeat(Math.max(0, size.columns - stats.length - 1))}` : '',
      source: windowDiff(lines, offset, diffRows()),
      path,
      note,
      hint: HINT,
      diffRows: diffRows(),
      acked,
    }
  }

  on('session.start', async ($, e, next) => {
    const load = async () => {
      // Without --no-optional-locks this poll takes the index lock and can fail Claude's own git commands.
      const status = await $.process.run(['git', '--no-optional-locks', 'status', '--porcelain=v1', '-z', '-b', '-uall'])
      if (status.exitCode !== 0) return { z: '', diff: '', note: 'not a git repository' }
      const parsed = parseStatus(status.stdout)
      branch = parsed.branch
      files = parsed.files
      const file = files[selectedIndex()]
      selected = file?.path ?? ''
      if (!file) return { z: status.stdout, diff: '', note: 'nothing changed' }
      const diff = await $.process.run(file.x === '?'
        ? ['git', 'diff', '--no-index', '--', '/dev/null', file.path]
        : ['git', '--no-optional-locks', 'diff', 'HEAD', '--', file.path])
      return { z: status.stdout, diff: diff.stdout, note: '' }
    }

    refresh = async () => {
      if (!isOpen) return
      isStale = true
      if (isRefreshing) return
      isRefreshing = true
      try {
        while (isStale) {
          isStale = false
          const loaded = await load()
          if (loaded.note === 'not a git repository') files = []
          const seen = `${selected}\0${loaded.z}\0${loaded.diff}`
          if (seen === lastSeen) continue
          lastSeen = seen
          note = loaded.note
          lines = parseDiff(loaded.diff)
          scrollTo(offset)
          $.ui.invalidate('ui.render')
        }
      } catch (error) {
        note = `git failed: ${error instanceof Error ? error.message : String(error)}`
        $.ui.invalidate('ui.render')
      } finally {
        isRefreshing = false
      }
    }

    $.clock.every(POLL_MS, () => { void refresh() })
    return next(e)
  })

  on('ui.close', { id: PANE }, async ($, e, next) => {
    const closed = await next(e)
    isOpen = false
    return closed
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    // The other surfaces have no Client, so they keep the bundled panel's own body.
    if (e.surface !== 'terminal' && e.surface !== 'desktop') return next(e)
    const { Client } = $.ui.resolve(e)
    size = { columns: e.props.bodyColumns, rows: e.props.scroll.bodyRows }
    if (!isOpen) {
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
      else if (key === ' ' || key === 'space') {
        const file = files[selectedIndex()]
        if (file) {
          const staged = await $.process.run(isFullyStaged(file)
            ? ['git', 'reset', '-q', '--', file.path]
            : ['git', 'add', '--', file.path])
          if (staged.exitCode !== 0) await $.ui.toast(staged.stderr.trim() || 'git could not stage that')
        }
      } else if (key === 'L') {
        // setsid -f returns at once and leaves a window that outlives this session.
        await $.process.run(['setsid', '-f', 'ghostty', `--working-directory=${await $.session.cwd()}`, '-e', 'lazygit'])
      }
    }

    void refresh()
    return { props: viewProps() }
  })
}
