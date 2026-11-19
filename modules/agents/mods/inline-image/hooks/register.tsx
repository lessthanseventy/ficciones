import type { Register } from 'claude-code'

import { rowsFor } from './picture'

type Picture = { png: string; columns: number; rows: number; path: string }

const COLUMNS = 72
const MAX_BYTES = 2 * 1024 * 1024

export const register: Register = on => {
  const drawn = new Map<string, Picture[]>()

  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    const row = await next(e)
    const p = e.props

    if (p.tool !== 'SendUserFile' || p.isRunning || p.isErrored || e.surface !== 'terminal') {
      return row
    }

    let pictures = drawn.get(p.tool_use_id)

    if (pictures === undefined) {
      pictures = []
      const files = (p.input as { files?: unknown }).files
      const paths = Array.isArray(files) ? files.filter((f): f is string => typeof f === 'string') : []

      for (const path of paths.filter(f => f.toLowerCase().endsWith('.png')).slice(0, 4)) {
        try {
          const { base64 } = await $.fs.read(path, { as: 'bytes' })

          if ((base64.length * 3) / 4 > MAX_BYTES || base64.length < 32) {
            continue
          }

          const head = (Uint8Array as unknown as { fromBase64: (s: string) => Uint8Array }).fromBase64(
            base64.slice(0, 32),
          )
          const rows = rowsFor(head, COLUMNS)

          if (rows === null) {
            continue
          }

          pictures.push({ png: base64, columns: COLUMNS, rows, path })
        } catch (err) {
          $.ui.log(`inline-image: ${path}: ${String(err)}`)
        }
      }

      // the row is first drawn before the call's input has arrived whole
      if (paths.length > 0) {
        drawn.set(p.tool_use_id, pictures)
      }
    }

    if (pictures.length === 0) {
      return row
    }

    const { Box, Image } = $.ui.resolve(e)

    return (
      <Box flexDirection="column">
        {row}
        {pictures.map(pic => (
          <Image source={{ png: pic.png }} columns={pic.columns} rows={pic.rows} alt={pic.path} />
        ))}
      </Box>
    )
  })
}
