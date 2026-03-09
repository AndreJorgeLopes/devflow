---
id: FEAT-finish-feature-checkpoint-discipline
title: "Finish Feature: Pre-PR Checkpoint Discipline"
priority: P1
category: feature
status: done
depends_on:
  - ARCH-pr-creation-vcs-detection
estimated_effort: S
files_touched:
  - devflow-plugin/commands/finish-feature.md
completed_date: "2026-03-06"
---

# Finish Feature: Pre-PR Checkpoint Discipline

## Context

The `finish-feature` skill previously ran straight through from verification to PR creation with no pause for human review. This meant the agent could create a PR before the developer had a chance to review the diff summary or approve the PR description.

## What Was Built

Added a mandatory **CHECKPOINT step** between commit and PR creation in `finish-feature.md`:

- Presents a structured summary: branch, commits, files changed, key diff summary
- Shows draft PR/MR title and description
- **Waits for explicit user approval** before pushing and creating the PR/MR

Additionally, `finish-feature.md` was updated as part of ARCH-pr-creation-vcs-detection to support VCS-aware PR/MR creation (GitHub `gh` vs GitLab `glab`).

## Why

Prevents the agent from creating PRs without the developer's knowledge or approval. Gives a final human checkpoint to catch issues the automated checks missed (wrong description, wrong base branch, incomplete changes).

## Pattern

This checkpoint pattern should be applied to other skills that have irreversible terminal actions. See also: the same review step in `create-pr.md`.
