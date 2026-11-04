import type { Register } from 'claude-code'

import { parseFrame, tmuxKey } from './frame'
import type { Key, Run } from './frame'

// The id the bundled diff panel opens its pane under. Drawing it from here keeps
// that plugin's auto-open, /diff and close behaviour and replaces only the body.
const PANE = 'diff'
const SOCKET = 'cc-lazygit'
const POLL_MS = 150
const HINT = 'click to type · esc leaves · ctrl+g is lazygit’s esc'

export const register: Register = (on, options) => {
  let session = ''
  let size = { columns: 0, rows: 0 }
  let rows: Run[][] = []
  let lastCapture = ''
  let acked = 0
  let isPolling = false
  let sent: Promise<unknown> = Promise.resolve()

  const tmux = (run: (argv: readonly string[]) => Promise<{ exitCode: number; stdout: string }>, ...args: string[]) =>
    run(['tmux', '-L', SOCKET, '-f', '/dev/null', ...args])

  on('session.start', async ($, e, next) => {
    session = `s${(await $.session.id()).replace(/[^a-zA-Z0-9]/g, '')}`
    const run = (argv: readonly string[]) => $.process.run(argv)
    const config = `${$.plugin.root}/hooks/lazygit.yml`
    const base = (await run(['lazygit', '--print-config-dir'])).stdout.trim()

    const ensure = async () => {
      if ((await tmux(run, 'has-session', '-t', session)).exitCode === 0) return
      await tmux(run, 'new-session', '-d', '-s', session, '-x', String(size.columns), '-y', String(size.rows), '-c', await $.session.cwd(),
        `while :; do lazygit --use-config-file='${base}/config.yml,${config}'; sleep 1; done`)
      await tmux(run, 'set-option', '-t', session, 'status', 'off')
    }

    $.clock.every(POLL_MS, async () => {
      if (isPolling || size.columns === 0) return
      isPolling = true
      try {
        await ensure()
        const { stdout } = await tmux(run, 'capture-pane', '-e', '-p', '-t', session, ';',
          'display-message', '-p', '-t', session, '#{cursor_x} #{cursor_y} #{cursor_flag}')
        if (stdout === lastCapture) return
        lastCapture = stdout
        const lines = stdout.trimEnd().split('\n')
        const [x, y, shown] = (lines.pop() ?? '').split(' ').map(Number)
        rows = parseFrame(lines.join('\n'), size.rows, shown ? { x: x ?? 0, y: y ?? 0 } : undefined)
        $.ui.invalidate('ui.render')
      } finally {
        isPolling = false
      }
    })

    return next(e)
  })

  on('session.end', async ($, e, next) => {
    // Without this the next poll sees the session gone and starts it again.
    size = { columns: 0, rows: 0 }
    await tmux(argv => $.process.run(argv), 'kill-session', '-t', session).catch(() => {})
    return next(e)
  })

  on('ui.close', { id: PANE }, async ($, e, next) => {
    const closed = await next(e)
    size = { columns: 0, rows: 0 }
    await tmux(argv => $.process.run(argv), 'kill-session', '-t', session).catch(() => {})
    return closed
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Client } = $.ui.resolve(e)
    const columns = e.props.bodyColumns
    const height = Math.max(1, e.props.scroll.bodyRows - 1)
    if (columns !== size.columns || height !== size.rows) {
      size = { columns, rows: height }
      void tmux(argv => $.process.run(argv), 'resize-window', '-t', session, '-x', String(columns), '-y', String(height)).catch(() => {})
    }

    return <Client key="term" module="./terminal.tsx" props={{ rows, hint: HINT, acked }} width="100%" />
  })

  on('ui.message', { requestId: PANE }, async ($, e) => {
    const { keys } = e.data as { keys: (Key & { n: number })[] }
    const fresh = keys.filter(k => k.n > acked)
    if (fresh.length === 0) return {}
    acked = fresh[fresh.length - 1]!.n
    sent = sent.then(() =>
      tmux(argv => $.process.run(argv), 'send-keys', '-t', session, '--', ...fresh.map(tmuxKey)))
    await sent

    return { props: { rows, hint: HINT, acked } }
  })
}
