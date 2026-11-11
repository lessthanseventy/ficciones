import type { Register } from 'claude-code'

import { clamp, countDiff, deltaArgv, emptyDiffNote, fitRows, parseAnsi, parseDiff, parseStatus, printable, revealTop, splitDiff, tailPath, wrapRows } from './changes'
import type { DiffLine, Run } from './changes'
import { landPrompt, noteBlock, noteHead } from './review'
import type { Note } from './review'
import type { Input, Section } from './view'

const PANE = 'review'
const COMMAND = 'land'
const OPEN = { id: PANE, title: 'Review' }
const POLL_MS = 2000
const MAX_FILE_ROWS = 10
const MAX_NOTE_ROWS = 5
// Each untracked file costs a process on every poll; an unignored build folder must not cost thousands.
const MAX_UNTRACKED_DIFFS = 30
const CONTEXT_ROWS = 3
// The pane's keys, each a button under it: a hotkey is one lowercase letter.
const KEYS = [['j', 'next'], ['k', 'prev'], ['d', 'down'], ['u', 'up'], ['n', 'note']] as const

type Diff = { text: string; lines: DiffLine[]; adds: number; dels: number }

const diffOf = (text: string): Diff => {
  const lines = parseDiff(text)
  return { text, lines, ...countDiff(lines) }
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`

export const register: Register = on => {
  let size = { columns: 0, rows: 0 }
  // The repository under review, its branch, the ref it is read against, and the commits since they parted.
  let repo = ''
  let branch = ''
  let base = ''
  let commits = 0
  let files: { path: string; diff: Diff }[] = []
  let file = ''
  let filesTop = 0
  let note = ''
  let rows: Run[][] = []
  let starts: number[] = []
  let renderedKey = ''
  let offset = 0
  let acked = 0
  let isOpen = false
  let canDraw = false
  // Whether the view has the keyboard, read from where input lands: the engine says nothing when a click gives it.
  let hasKeys = false
  let notes: Note[] = []
  // The diff line a click chose, by its row in delta's drawing.
  let picked: { file: string; row: number; at: number; code: string } | null = null
  // A note whose line the next drawing of its file scrolls to.
  let sought: Note | null = null
  let isWriting = false
  let isRefreshing = false
  let isStale = false
  let refresh: () => Promise<void> = async () => {}
  let open: () => Promise<void> = async () => {}
  // A terminal sends one notch of the wheel as a burst of events; over the list the burst is one step.
  const NOTCH_MS = 40
  let wheeled = { at: 0, by: 0 }

  const current = () => files.find(f => f.path === file)?.diff
  const fileRows = () => clamp(files.length, 1, Math.min(MAX_FILE_ROWS, Math.floor(size.rows / 4)))
  const noteRows = () => Math.min(notes.length, MAX_NOTE_ROWS) + (notes.length > MAX_NOTE_ROWS ? 1 : 0)
  // The head, two boxes' top and bottom edges, and the keys.
  const diffRows = () => Math.max(1, size.rows - fileRows() - noteRows() - 6 - (isWriting ? 1 : 0))
  const scrollTo = (next: number) => { offset = clamp(next, 0, rows.length - diffRows()) }
  const reveal = () => {
    filesTop = revealTop(filesTop, Math.max(0, files.findIndex(f => f.path === file)), files.length, fileRows())
  }
  const pickFile = (index: number) => {
    const path = files[clamp(index, 0, files.length - 1)]?.path
    if (path === undefined || path === file) return
    file = path
    offset = 0
  }
  const rowOf = ({ at, code }: Pick<Note, 'at' | 'code'>) => {
    const lines = current()?.lines ?? []
    const i = lines.findIndex(l => l.at === at && l.text === code)
    return i < 0 ? -1 : starts[i + lines[i]!.hunk] ?? -1
  }

  // A line with a note, and the line a click chose, wear a mark in the column delta leaves blank.
  const marked = (window: Run[][]) => {
    const noted = new Set(notes.filter(n => n.file === file).map(rowOf))
    const chosen = picked?.file === file ? starts[picked.row] : undefined
    return window.map((runs, i) => {
      const mark: Run | null = offset + i === chosen ? { t: '▶', c: 'claude', bold: true } : noted.has(offset + i) ? { t: '●', c: 'remember' } : null
      const [first, ...rest] = runs
      return mark && first ? [mark, { ...first, t: first.t.slice(1) }, ...rest] : runs
    })
  }

  // A click on a row of the diff chooses the line it draws.
  const pick = (viewRow: number) => {
    const row = starts.findLastIndex(start => start <= offset + viewRow)
    const line = (current()?.lines ?? []).find((l, i) => i + l.hunk === row)
    picked = line ? { file, row, at: line.at, code: line.text } : null
  }

  const viewProps = () => {
    const first = clamp(filesTop, 0, files.length - fileRows())
    const diff = current()
    // A box's top edge holds its title: a corner and a dash before it, the rule after it to the far corner.
    const room = Math.max(0, size.columns - 2)
    const rule = (taken: number) => (room > taken ? ` ${'─'.repeat(room - taken - 1)}` : '')
    const filesHead = `files · ${files.length}`.slice(0, room)
    const adds = diff?.adds ? `  +${diff.adds}` : ''
    const dels = diff?.dels ? ` -${diff.dels}` : ''
    const left = Math.max(0, room - adds.length - dels.length)
    const title = printable(file.split('/').pop() ?? '').slice(0, left)
    const folder = file.includes('/') ? `  ${printable(file.slice(0, file.lastIndexOf('/')))}` : ''
    const where = title.length + folder.length <= left ? folder : ''
    // a file with a note leads with its mark, and the rest stand clear of the column once one does
    const lead = (path: string) => (notes.length === 0 ? '' : notes.some(n => n.file === path) ? '● ' : '  ')
    const section: Section = {
      head: filesHead,
      rule: rule(filesHead.length),
      isFocused: hasKeys,
      first,
      empty: 'nothing to review',
      rows: files.slice(first, first + fileRows()).map(({ path, diff }) => {
        const [plus, minus] = [diff.adds ? ` +${diff.adds}` : '', diff.dels ? ` -${diff.dels}` : '']
        const width = Math.max(1, size.columns - lead(path).length - plus.length - minus.length)
        const text = tailPath(printable(path), width).padEnd(width)
        // a path's folders are drawn dim, so the name is what the eye lands on
        const cut = text.lastIndexOf('/') + 1
        return { lead: lead(path), dim: text.slice(0, cut), label: text.slice(cut), adds: plus, dels: minus, isSelected: path === file }
      }),
    }
    return {
      title,
      where,
      adds,
      dels,
      rule: title === '' ? '─'.repeat(room) : rule(title.length + where.length + adds.length + dels.length),
      columns: size.columns,
      rows: marked(fitRows(rows.slice(offset, offset + diffRows()))),
      diffRows: diffRows(),
      note: file !== '' && diff?.lines.length === 0 ? emptyDiffNote(diff.text) : '',
      files: section,
      acked,
    }
  }

  const head = (): Run[] => {
    if (note !== '') return [{ t: note, c: 'warning' }]
    if (base === '') return [{ t: 'reading the branch', dim: true }]
    const [adds, dels] = [files.reduce((sum, f) => sum + f.diff.adds, 0), files.reduce((sum, f) => sum + f.diff.dels, 0)]
    return [
      { t: printable(branch), c: 'claude', bold: true },
      { t: ' against ', dim: true },
      { t: printable(base), c: 'remember', bold: true },
      { t: ` · ${plural(commits, 'commit')} · ${plural(files.length, 'file')}`, dim: true },
      { t: ` +${adds}`, c: 'success' },
      { t: ` -${dels}`, c: 'error' },
      { t: ` · ${printable(repo.split('/').pop() ?? '')}`, dim: true },
    ]
  }

  on('session.start', async ($, e, next) => {
    const load = async () => {
      // The pane opened on another repository while this reads leaves it for the next pass.
      const at = repo
      // Without --no-optional-locks this poll takes the index lock and can fail Claude's own git commands.
      const git = (...args: string[]) => $.process.run(['git', '--no-optional-locks', '-c', 'core.quotePath=false', ...args], { cwd: at })
      const named = async (ref: string) => {
        const out = await git('rev-parse', '--abbrev-ref', ref)
        return out.exitCode === 0 ? out.stdout.trim() : ''
      }
      const here = at === '' ? '' : await named('HEAD')
      // The remote's default branch, else what this one pushes to, else a local main: the first this branch parted from.
      let fork: { ref: string; sha: string } | null = null
      for (const ref of here === '' ? [] : [await named('origin/HEAD'), await named('@{upstream}'), 'main', 'master']) {
        if (ref === '' || ref === here) continue
        const sha = await git('merge-base', 'HEAD', ref)
        if (sha.exitCode !== 0 || sha.stdout.trim() === '') continue
        fork = { ref, sha: sha.stdout.trim() }
        break
      }
      if (!fork) {
        if (at !== repo) return
        files = []
        base = ''
        note = here === '' ? 'not a git repository' : `nothing to review ${here === 'HEAD' ? 'a detached HEAD' : here} against: no remote branch, and no other main`
      } else {
        const status = await git('status', '--porcelain=v1', '-z', '-uall')
        // against the commit they parted at, so what the base has gained since is not shown as removed
        const tracked = await git('diff', fork.sha, '--no-renames', '--no-color', '--no-ext-diff')
        const count = await git('rev-list', '--count', `${fork.sha}..HEAD`)
        const texts = splitDiff(tracked.stdout)
        for (const untracked of parseStatus(status.stdout).filter(f => f.isUntracked).slice(0, MAX_UNTRACKED_DIFFS)) {
          const diff = await $.process.run(['git', 'diff', '--no-index', '--no-color', '--no-ext-diff', '--', '/dev/null', untracked.path], { cwd: at })
          texts.set(untracked.path, diff.stdout)
        }
        if (at !== repo) return
        const before = new Map(files.map(f => [f.path, f.diff]))
        files = [...texts].map(([path, text]) => ({ path, diff: before.get(path)?.text === text ? before.get(path)! : diffOf(text) }))
        branch = here === 'HEAD' ? 'detached' : here
        base = fork.ref
        commits = Number(count.stdout.trim()) || 0
        note = ''
      }
      if (!files.some(f => f.path === file)) file = files[0]?.path ?? ''

      const text = current()?.text ?? ''
      const key = `${at}\0${file}\0${size.columns}\0${text}`
      if (key !== renderedKey) {
        renderedKey = key
        rows = []
        starts = []
        if (current()?.lines.length) {
          const drawn = await $.process.run(deltaArgv(size.columns), { stdin: text })
          if (at !== repo) return
          // delta leads with the blank row it puts before every hunk.
          ;({ rows, starts } = wrapRows(parseAnsi(drawn.stdout, size.columns).slice(1), size.columns))
        }
      }
      if (sought?.file === file) {
        const row = rowOf(sought)
        if (row >= 0) offset = Math.max(0, row - CONTEXT_ROWS)
        sought = null
      }
    }

    refresh = async () => {
      if (!isOpen) return
      isStale = true
      if (isRefreshing) return
      isRefreshing = true
      try {
        while (isStale) {
          isStale = false
          const seen = JSON.stringify([renderedKey, note, files.map(f => f.path), branch, base, commits, offset])
          await load()
          scrollTo(offset)
          if (seen !== JSON.stringify([renderedKey, note, files.map(f => f.path), branch, base, commits, offset])) $.ui.invalidate('ui.render')
        }
      } catch (error) {
        note = `could not read the branch: ${error instanceof Error ? error.message : String(error)}`
        $.ui.invalidate('ui.render')
      } finally {
        isRefreshing = false
      }
    }

    // The review is of the repository the session is in when it is asked for.
    open = async () => {
      const top = await $.process.run(['git', 'rev-parse', '--show-toplevel'], { cwd: await $.session.cwd() })
      const root = top.exitCode === 0 ? top.stdout.trim() : ''
      if (root !== repo) {
        repo = root
        files = []
        file = ''
        base = ''
        notes = []
        picked = null
        renderedKey = ''
        offset = 0
        filesTop = 0
      }
      const { isPlaced } = await $.ui.open({ ...OPEN, focus: true })
      if (!isPlaced) return
      isOpen = true
      void refresh()
    }

    $.clock.every(POLL_MS, () => { void refresh() })
    // VS Code and mobile have no Client to draw this pane with.
    canDraw = e.surface === 'terminal' || e.surface === 'desktop'
    if (canDraw) await $.command.register({ name: COMMAND, description: 'Review the whole branch against its base before it lands: leave notes on lines of the diff, send them, then ask for the pull request', immediate: true })
    return next(e)
  })

  on('command.run', { command: COMMAND }, async $ => {
    if (isOpen) await $.ui.close({ id: PANE })
    else await open()
    return {}
  })

  on('ui.close', { id: PANE }, async (_, e, next) => {
    const closed = await next(e)
    isOpen = false
    isWriting = false
    return closed
  })

  const act = (key: string) => {
    if (key === 'n') isWriting = file !== ''
    else if (key === 'j') pickFile(files.findIndex(f => f.path === file) + 1)
    else if (key === 'k') pickFile(files.findIndex(f => f.path === file) - 1)
    else if (key === 'd') scrollTo(offset + 1)
    else if (key === 'u') scrollTo(offset - 1)
    reveal()
  }

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    if (e.surface !== 'terminal' && e.surface !== 'desktop') return next(e)
    const { Client, Box, Text, Button, Input } = $.ui.resolve(e)
    const chosen = picked?.file === file ? picked : null
    if (hasKeys !== e.props.isFocused) {
      hasKeys = e.props.isFocused
      // Escape hands the keys back, and a note half written goes with them.
      if (!hasKeys) isWriting = false
    }
    // a box's edges take a column each side
    const columns = Math.max(1, e.props.bodyColumns - 2)
    const isResized = columns !== size.columns
    size = { columns, rows: e.props.scroll.bodyRows }
    if (!isOpen || isResized) {
      isOpen = true
      void refresh()
    }
    const range = { repo, branch, base }
    const press = (text: string) => async () => {
      await $.prompt.submit({ text, asUser: true })
    }
    return (
      <Box flexDirection="column">
        <Text wrap="truncate-end">
          {head().map(r => <Text color={r.c} weight={r.bold ? 'bold' : undefined} dimColor={r.dim}>{r.t}</Text>)}
        </Text>
        <Client key="review" module="./view.tsx" props={viewProps()} width="100%" />
        {notes.slice(0, MAX_NOTE_ROWS).map((kept, i) => (
          <Box>
            <Button plain key={`drop-${i}`} label="✕" onPress={async () => {
              notes = notes.filter(n => n !== kept)
              $.ui.invalidate('ui.render')
            }} />
            <Box marginLeft={1} marginRight={1}>
              <Button plain key={`goto-${i}`} label={printable(noteHead(kept))} onPress={async () => {
                file = kept.file
                sought = kept
                reveal()
                await refresh()
                $.ui.invalidate('ui.render')
              }} />
            </Box>
            <Text wrap="truncate-end">{printable(kept.note)}</Text>
          </Box>
        ))}
        {notes.length > MAX_NOTE_ROWS ? <Text dimColor>  and {notes.length - MAX_NOTE_ROWS} more, all sent together</Text> : null}
        {isWriting ? (
          <Input
            key="note"
            autoFocus
            label={`note on ${printable(file.split('/').pop() ?? '')}${chosen ? `:${chosen.at}` : ''}`}
            placeholder="what Claude should change here, or answer"
            submitLabel="keep"
            onSubmit={value => {
              const said = value.trim()
              if (said !== '') notes = [...notes, { file, at: chosen?.at ?? 0, code: chosen?.code ?? '', note: said }]
              isWriting = false
              picked = null
              $.ui.invalidate('ui.render')
              // the field gave the keys to the prompt as it closed, and the next note wants them here
              void $.ui.open({ ...OPEN, focus: true })
            }}
          />
        ) : null}
        <Box>
          {hasKeys ? <Text inverse weight="bold" color="claude"> REVIEW </Text> : <Text dimColor>○ click</Text>}
          {KEYS.map(([hotkey, label]) => (
            <Box marginLeft={1}>
              <Button plain dimColor={!hasKeys} key={`key-${hotkey}`} hotkey={hotkey} label={label} onPress={async () => {
                act(hotkey)
                await refresh()
                $.ui.invalidate('ui.render')
                // autoFocus is taken only as the pane takes the keys, which by now it has
                if (isWriting) await $.ui.focus({ requestId: PANE, key: 'note' }).catch(() => {})
              }} />
            </Box>
          ))}
          {notes.length > 0 ? (
            <Box marginLeft={1}>
              <Button plain key="send" hotkey="s" label={`send ${plural(notes.length, 'note')}`} onPress={async () => {
                const sent = notes
                notes = []
                $.ui.invalidate('ui.render')
                await press(noteBlock(sent, range))()
              }} />
            </Box>
          ) : base !== '' && files.length > 0 ? (
            // offered only once no note is waiting, so a pull request is never asked for over one
            <Box marginLeft={1}>
              <Button plain key="land" hotkey="p" label="pull request" onPress={press(landPrompt(range, commits, files.length))} />
            </Box>
          ) : null}
        </Box>
      </Box>
    )
  })

  // The body never overflows: the view draws its own windows of rows, so the wheel acts on the box it is over.
  on('ui.scroll', { requestId: PANE }, async ($, e) => {
    // the head takes the body's first row
    const at = (e.pointer?.row ?? 0) - 1
    if (at < diffRows() + 2) scrollTo(offset + e.by)
    else {
      const now = Date.now()
      const by = Math.sign(e.by)
      const isSameNotch = by === wheeled.by && now - wheeled.at < NOTCH_MS
      wheeled = { at: now, by }
      if (isSameNotch) return {}
      pickFile(files.findIndex(f => f.path === file) + by)
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
    // A click here is the person asking for the pane's keys.
    await $.ui.open({ ...OPEN, focus: true })
    for (const { row, diff } of fresh) {
      if (diff !== undefined) pick(diff)
      if (row === undefined) continue
      pickFile(row)
      reveal()
    }
    void refresh()
    return { props: viewProps() }
  })
}
