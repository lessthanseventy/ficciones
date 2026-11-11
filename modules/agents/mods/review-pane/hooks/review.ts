// A note the person left on a line of the review's diff, for the model; `at` is 0 for a note on the whole file.
export type Note = { file: string; at: number; code: string; note: string }
// What is under review: the branch, the ref it is read against, and the repository's root.
export type Range = { repo: string; branch: string; base: string }

export const noteHead = ({ file, at }: Note) => `${file}${at > 0 ? `:${at}` : ''}`

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`

/** The notes as the one message that carries them to the model. */
export const noteBlock = (notes: Note[], { repo, branch, base }: Range) => [
  `I reviewed ${branch} against ${base} in ${repo} and left ${plural(notes.length, 'note')} on its diff. Address each one, and say what you did about it:`,
  '',
  ...notes.map(n => `- ${noteHead(n)}${n.code === '' ? '' : ` \`${n.code}\``}: ${n.note}`),
].join('\n')

/** The message that asks for the pull request, once the review has no notes left. */
export const landPrompt = ({ repo, branch, base }: Range, commits: number, files: number) =>
  `I reviewed ${branch} against ${base} in ${repo} (${plural(commits, 'commit')}, ${plural(files, 'file')}) and have no notes left. `
  + 'Land it as a pull request, by this repository\'s own rules for branches and pull requests. Ask me before you push, and again before you open it.'
