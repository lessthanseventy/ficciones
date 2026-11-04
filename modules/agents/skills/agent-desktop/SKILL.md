---
name: agent-desktop
description: See and operate desktop apps through the accessibility tree, as JSON with element refs. Use to read what the Astal shell, Floorp, or any native app is showing, or to verify a desktop change, instead of a screenshot.
---

Before first use, run `agent-desktop skills get desktop` and `agent-desktop skills get platform`; they match the installed version.

The live desktop is the human's:

- **Read freely:** `status`, `list-apps`, `list-windows`, `snapshot`, `find`, `get`, `is`.
- **Act only on an app you launched for the test, or when the human asked for that action.** Everything else goes in a throwaway session.
- **Never `--headed`, `press`, or a pointer command on the live desktop.** They send real input.

A throwaway session is `mise run desktop:headless -- <command>`: a private compositor, session bus and accessibility bus, with `agent-desktop` and the app run inside it. Never build one by hand. A private bus that keeps the real `XDG_RUNTIME_DIR` deletes the live accessibility socket when it exits.

`--app` takes the name `list-apps` prints. The shell is `gjs-console`; it has several windows, so pass `--window-id` from `list-windows`.

Snapshots hold whatever is on screen, and each is also saved under `~/.agent-desktop/snapshots`. Keep them out of logs and commits, and clear that directory after reading a window with private content.
