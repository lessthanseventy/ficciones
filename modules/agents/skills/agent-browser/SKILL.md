---
name: agent-browser
description: Drive a headless Chromium from the shell with element refs. Use to test a web app end to end, check a real rendered page, or read its accessibility tree. Not for Floorp, which is Gecko; that has `mise run floorp:e2e`.
---

Before first use, run `agent-browser skills get core`; it matches the installed version.

Pass your own `--session <name>` so parallel agents do not share a browser, and run `agent-browser --session <name> close` when done. Take refs from the latest `snapshot -i` rather than guessing them.

Do not attach to the human's browser with `--cdp` or `--auto-connect` unless asked. It carries their logins.
