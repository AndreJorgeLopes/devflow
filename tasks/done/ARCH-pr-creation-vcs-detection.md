---
id: ARCH-pr-creation-vcs-detection
title: "PR Creation With Correct VCS Tool"
priority: P1
category: architecture
status: done
depends_on: []
estimated_effort: S
files_touched:
  - devflow-plugin/commands/create-pr.md
  - devflow-plugin/commands/finish-feature.md
  - lib/utils.sh
completed_date: "2026-03-06"
---

# PR Creation With Correct VCS Tool

## What Was Built

Implemented VCS-agnostic PR/MR creation across devflow skills:

1. **`lib/utils.sh`**: Added `detect_vcs_provider()` and `get_vcs_pr_term()` functions. Provider is detected from `git remote get-url origin` — supports github, gitlab, bitbucket, azure, unknown.

2. **`devflow-plugin/commands/create-pr.md`**: Replaced hardcoded `gh pr create` with VCS detection logic. Now uses `gh pr create` for GitHub, `glab mr create` for GitLab, and outputs a compare URL for unknown providers.

3. **`devflow-plugin/commands/finish-feature.md`**: Applied the same VCS-aware pattern. Also includes the pre-PR checkpoint step (see FEAT-finish-feature-checkpoint-discipline).

## Original task file

See git history for the original spec at tasks/P1/ARCH-pr-creation-vcs-detection.md.
