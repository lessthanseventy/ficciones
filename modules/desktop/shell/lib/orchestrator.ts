// The bar's orchestrator cell: babylon's board and the orchestrator's session record, in words (lib/orchestrator-core.ts).
import { createComputed, createState } from "ags"
import { execAsync } from "ags/process"
import { board } from "./board"
import { sessions } from "./sessions"
import { cell, followTold, type Told } from "./orchestrator-core"

const SESSION = "orchestrator"

const [pane, setPane] = createState<string | null>(null)
const [told, setTold] = createState<Told>(null)

// the board does not name the orchestrator's pane: ask tmux for the one in its session
async function findPane() {
  const b = board.peek()
  if (!b?.orchestrator?.running || !b.socket) return setPane(null)
  try {
    const out = await execAsync(["tmux", "-S", b.socket, "list-panes", "-t", SESSION, "-F", "#{pane_id}"])
    setPane(out.split("\n")[0] || null)
  } catch { setPane(null) }
}
board.subscribe(() => void findPane())
void findPane()

const session = createComputed(() => sessions().find((s) => s.pane === pane()) ?? null)

session.subscribe(() => setTold(followTold(told.peek(), session.peek())))

/** A line was told at `at`: the cell says `on it`, then `answered`, until the next click on it. The turn may already be running. */
export const noteTold = (at: number) => setTold(followTold({ at, phase: "sent" }, session.peek()))
export const noteShown = () => setTold(null)

export const orchestratorCell = createComputed(() => cell(board(), session(), told()))
