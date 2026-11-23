// The bar's orchestrator cell: babylon's board and the orchestrator's session record, in words (lib/orchestrator-core.ts).
import { createComputed, createState } from "ags"
import { execAsync } from "ags/process"
import { board } from "./board"
import { sessions } from "./sessions"
import { cell } from "./orchestrator-core"

const SESSION = "orchestrator"

const [pane, setPane] = createState<string | null>(null)

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

export const orchestratorCell = createComputed(() => cell(board(), session()))
