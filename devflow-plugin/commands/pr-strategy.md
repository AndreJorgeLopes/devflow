---
description: [devflow v0.1.0] View or reset your PR/MR description strategy preference for this project
---

View or reset the PR/MR description strategy preference for the current project.

## Steps

1. **Detect project name.** Run:
   ```bash
   basename "$(git rev-parse --show-toplevel)"
   ```
   Store the result as `<project>` for use in all subsequent steps.

2. **Recall existing preference from Hindsight.** Use the `recall` tool:
   ```
   recall("<project>: PR description strategy", tags=["pr-strategy"])
   ```

3. **If a strategy is found:** Display the current strategy to the user and ask via `AskUserQuestion`:
   - **Keep** — Leave the current preference as-is (stop here)
   - **Change** — Pick a new strategy (continue to step 4)
   - **Clear** — Remove the preference entirely by calling `delete_memory` on the matched memory, confirm deletion, and stop

4. **If "Change" was chosen, or no existing strategy was found:** Present the strategy selector via `AskUserQuestion` with these options:
   - **Auto-generate (Recommended)** — Use the default devflow template (Summary / Changes / Testing / Ticket / Checklist), filled from diff analysis
   - **Use repo template** — Search the codebase for PR/MR templates at standard locations, parse sections, fill from diff
   - **Custom path** — User specifies a template file path to use

5. **If "Use repo template" is chosen:** Search these locations in order using the Glob tool:
   1. `.github/PULL_REQUEST_TEMPLATE.md`
   2. `.github/PULL_REQUEST_TEMPLATE/*.md`
   3. `.gitlab/merge_request_templates/*.md`
   4. `PULL_REQUEST_TEMPLATE.md` (repo root)
   5. `docs/pull_request_template.md`

   If multiple templates are found, present them via `AskUserQuestion` and let the user pick one.
   If none are found, inform the user and fall back to asking for a custom path or auto-generate.

6. **If "Custom path" is chosen:** Ask the user for the file path via `AskUserQuestion`. Verify the file exists by reading it. If it does not exist, report the error and ask again.

7. **Retain the choice in Hindsight.** Use `retain` with the appropriate value:
   - For auto-generate: `retain("<project>: PR description strategy = auto-generate", tags=["pr-strategy", "<project>"])`
   - For repo-template with a specific file: `retain("<project>: PR description strategy = repo-template:<relative-path>", tags=["pr-strategy", "<project>"])`
   - For custom: `retain("<project>: PR description strategy = custom:<path>", tags=["pr-strategy", "<project>"])`

   If an old memory was found in step 2, delete it first with `delete_memory` before retaining the new one.

8. **Confirm** the saved preference to the user. State which strategy was stored and for which project.

$ARGUMENTS
