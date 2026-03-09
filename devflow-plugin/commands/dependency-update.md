---
description: [devflow v0.1.0] Check if Brewfile, Formula, or install script need updating when project dependencies change.
---

You are checking whether devflow's dependency manifests are in sync with code changes.

## When to Run

Run this check when any of these files have changed:
- `lib/*.sh` (new tool dependencies)
- `Makefile` or `install.sh` (build/install changes)
- `package.json` or similar manifest files

## Steps

1. **Identify what changed.** Run:

   ```bash
   git diff --name-only HEAD~1..HEAD
   ```

   Look for changes in dependency-sensitive files.

2. **Check Formula/devflow.rb.** Review whether:
   - New `depends_on` entries are needed (e.g., new CLI tools)
   - The `install` method covers any new directories or files
   - The `caveats` section mentions any new optional tools

3. **Check the Brewfile** (if the project has one, or `~/Brewfile` for the user's system). Review whether:
   - New brew packages are needed
   - Layer comments are up to date

4. **Check install.sh.** Review whether:
   - New tool installations are covered
   - PATH setup handles new binaries

5. **Generate a report:**

   ```
   ## Dependency Sync Check

   ### Changed Files
   - [list of dependency-sensitive files that changed]

   ### Formula/devflow.rb
   - [OK / NEEDS UPDATE: reason]

   ### Brewfile
   - [OK / NEEDS UPDATE: reason]

   ### install.sh
   - [OK / NEEDS UPDATE: reason]

   ### Verdict: [IN SYNC / NEEDS UPDATES]
   ```

6. If updates are needed, list the specific changes required and offer to make them.

$ARGUMENTS
