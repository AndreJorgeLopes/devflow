---
description: "[devflow v0.1.0] Check sensitive files — review stale files and apply fixes"
---

You are checking sensitive files for staleness. This command reviews files that must stay in sync with source code changes.

## Steps

1. **Read the config.** Read `.devflow/sensitive-files.conf` in the project root. If it doesn't exist, tell the user: "No `.devflow/sensitive-files.conf` found. Run `devflow watch setup` to create one."

2. **Check for pending items.** Read `.devflow/pending-fixes.json` and `.devflow/pending-reviews.json` if they exist. These are queued by the background watcher.

3. **Run mechanical checks.** For each `mechanical` entry in the config:
   - Run the `check_cmd` (the 4th field) via Bash
   - If the command exits non-zero, flag the target as stale
   - Present the result with ✓ or ⚠ prefix

4. **Run semantic checks.** For each `semantic` entry in the config:
   - Read the target file and its source files
   - Use the check prompt (4th field) to evaluate freshness
   - If stale, generate a suggested fix

5. **Present summary.** Show all results:
   ```
   Sensitive File Check:
   ✓ lib/utils.sh — version consistent (0.1.0)
   ✓ plugin.json — version consistent (0.1.0)
   ⚠ CLAUDE.md — Project Structure may be stale
     Suggested: Add "lib/watch.sh" to the structure tree
   ```

6. **Offer to fix.** Use the `AskUserQuestion` tool to ask: "Apply suggested fixes?" (Options: "Yes, apply all", "Let me review each", "Skip for now")

7. **Clear pending files.** After processing, delete `.devflow/pending-fixes.json`, `.devflow/pending-reviews.json`, and `/tmp/devflow-pending-notified-*` for the current session.

## Important

- Mechanical checks (version strings) can be auto-fixed by running `devflow check-version` to identify mismatches and then updating the stale files.
- Semantic checks require reading the actual files and comparing against the source. Use the check prompt as guidance.
- Run semantic checks in parallel using the Agent tool where possible.
- This command can be invoked at any time, not just during finish-feature.

$ARGUMENTS
