---
id: FEAT-interactive-hindsight-seeding
title: "Interactive Hindsight Seeding on devflow up"
priority: P2
category: features
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - lib/services.sh
  - lib/seed.sh
---

# Interactive Hindsight Seeding on `devflow up`

## Context

After `devflow up` successfully starts services, the user should be prompted to seed Hindsight memory with the current project's files. This is especially important on first setup — new projects have no memories, and existing projects may have stale or deprecated memories that should be cleaned up. Currently, seeding is a separate manual step that users often forget.

## Problem Statement

There is no integration between `devflow up` (service lifecycle) and `devflow seed` (memory initialization). Users must remember to seed manually after starting services, leading to agents that start sessions without project context. Additionally, there is no mechanism to review, prune, or incrementally update existing memories — every seed is a full overwrite with no awareness of what already exists.

## Desired Outcome

- `devflow up` prompts the user to seed Hindsight after all services are healthy
- If memories already exist for the project, the user can interactively review them — keeping relevant ones and removing deprecated ones
- Only new or changed files are seeded (incremental seeding)
- A timestamp dotfile tracks the last seed to enable change detection
- The entire flow is skippable with a single keypress for users who don't want to seed

## Implementation Guide

### Step 1: Add seed prompt to `devflow up`

In `lib/services.sh`, after the health-check loop confirms all services are running, add a call to a new function `prompt_hindsight_seed`:

```bash
prompt_hindsight_seed() {
  local project_path="${1:-$(pwd)}"
  local project_name
  project_name="$(basename "$project_path")"

  read -r -p "Seed Hindsight memory with ${project_path} files? [Y/n] " response
  case "$response" in
    [nN]*) return 0 ;;
    *)     run_incremental_seed "$project_path" "$project_name" ;;
  esac
}
```

Accept an optional project path argument: `devflow up [--project <path>]`. Default to `$(pwd)`.

### Step 2: Check for existing memories

In `lib/seed.sh`, create `check_existing_memories`:

```bash
check_existing_memories() {
  local project_name="$1"
  local response
  response=$(curl -s http://localhost:8888/v1/recall -d "{\"query\": \"${project_name}\"}")

  local count
  count=$(echo "$response" | jq '.memories | length')

  if [[ "$count" -gt 0 ]]; then
    echo "Found ${count} existing memories for ${project_name}."
    review_existing_memories "$response"
  else
    echo "No existing memories found. Running full seed."
    return 1
  fi
}
```

### Step 3: Interactive multi-select for existing memories

Implement `review_existing_memories` with two UX paths:

**If `fzf` is available:**

```bash
# Pipe memories to fzf --multi with preview
echo "$memories" | jq -r '.memories[] | "\(.id)\t\(.title)\t\(.created_at)\t\(.content[:80])"' \
  | fzf --multi --header="Select memories to KEEP (Tab to toggle, Enter to confirm)" \
  --preview="echo {4}"
```

**Fallback (no fzf):**

```bash
# Numbered list with space-separated selection
echo "Select memories to KEEP (space-separated numbers, or 'all'):"
# Display: [1] title — date — first 80 chars
# Read input, parse selection
```

Memories NOT selected are deleted via Hindsight API.

### Step 4: Incremental seeding for new/changed files

Track last seed time in `.devflow-seed-timestamp` in the project directory:

```bash
run_incremental_seed() {
  local project_path="$1"
  local project_name="$2"
  local timestamp_file="${project_path}/.devflow-seed-timestamp"
  local last_seed=0

  if [[ -f "$timestamp_file" ]]; then
    last_seed=$(cat "$timestamp_file")
  fi

  # Find files modified since last seed
  local seed_files=("CLAUDE.md" "package.json" "README.md" "tsconfig.json")
  for f in "${seed_files[@]}"; do
    local filepath="${project_path}/${f}"
    if [[ -f "$filepath" ]]; then
      local mod_time
      mod_time=$(stat -f %m "$filepath" 2>/dev/null || stat -c %Y "$filepath" 2>/dev/null)
      if [[ "$mod_time" -gt "$last_seed" ]]; then
        seed_file "$filepath" "$project_name"
      fi
    fi
  done

  # Update timestamp
  date +%s > "$timestamp_file"
}
```

### Step 5: Add `.devflow-seed-timestamp` to `.gitignore` template

Ensure this dotfile is not committed. Add it to the project's `.gitignore` if not already present, or document that it should be ignored.

## Acceptance Criteria

- [ ] `devflow up` prompts "Seed Hindsight memory with <path> files? [Y/n]" after all services are healthy
- [ ] Answering 'n' or 'N' skips seeding entirely
- [ ] If memories exist, they are listed with title, date, and content preview
- [ ] User can select which memories to keep via `fzf --multi` (or numbered fallback)
- [ ] Unselected memories are deleted from Hindsight
- [ ] Only files modified since last seed are re-seeded (checked via `.devflow-seed-timestamp`)
- [ ] First-time seed (no timestamp file) seeds all standard files
- [ ] `.devflow-seed-timestamp` is created/updated after successful seed
- [ ] The `--project <path>` argument is accepted by `devflow up`
- [ ] Works when Hindsight API is unreachable (graceful failure with warning, not crash)

## Technical Notes

- Hindsight API endpoint for recall: `POST http://localhost:8888/v1/recall` with JSON body `{"query": "..."}`
- Hindsight API endpoint for delete: Check Hindsight docs — likely `DELETE http://localhost:8888/v1/memories/<id>`
- `fzf` detection: `command -v fzf &>/dev/null`
- macOS `stat` uses `-f %m` for modification time; Linux uses `-c %Y` — handle both
- The seed files list (CLAUDE.md, package.json, etc.) should be configurable, ideally in `~/.config/devflow/config.toml` or a project-level `.devflow.toml`
- Consider adding a `--skip-seed` flag to `devflow up` for CI/scripted environments

## Verification

```bash
# 1. Start fresh — no existing memories
devflow down && devflow up
# Expect: prompt to seed, full seed runs, timestamp file created

# 2. Run again immediately
devflow down && devflow up
# Expect: prompt to seed, "no files changed since last seed" message

# 3. Touch a file and re-seed
touch CLAUDE.md && devflow down && devflow up
# Expect: only CLAUDE.md is re-seeded

# 4. Verify existing memories review
# (After seeding, run up again — should show existing memories in multi-select)
devflow down && devflow up
# Expect: interactive list of existing memories

# 5. Skip seeding
devflow down && devflow up  # answer 'n'
# Expect: no API calls to Hindsight

# 6. Verify timestamp file
cat .devflow-seed-timestamp
# Expect: unix timestamp
```
