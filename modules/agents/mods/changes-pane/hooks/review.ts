// A note the person left on a line of a diff, for the model. `source` is '' for the working tree,
// else a commit; `at` is 0 for a note on the whole file.
export type Note = { repo: string; source: string; file: string; at: number; code: string; note: string }

export const noteHead = ({ file, at, source }: Note) => `${file}${at > 0 ? `:${at}` : ''}${source === '' ? '' : ` @ ${source}`}`

/** The notes as the text a prompt carries, grouped by repository. */
export const noteBlock = (notes: Note[]) => {
  const repos = [...new Set(notes.map(n => n.repo))]
  return [
    'Review notes I left on the diff in the changes pane:',
    ...repos.flatMap(repo => [
      '',
      `In ${repo}:`,
      ...notes.filter(n => n.repo === repo).map(n => `- ${noteHead(n)}${n.code === '' ? '' : ` \`${n.code}\``}: ${n.note}`),
    ]),
  ].join('\n')
}
