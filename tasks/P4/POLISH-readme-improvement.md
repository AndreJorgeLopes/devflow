---
id: POLISH-readme-improvement
title: "README Improvement — Pretty, Professional, Accurate"
priority: P4
category: polish
status: open
depends_on: []
estimated_effort: M
files_to_touch:
  - /Users/andrejorgelopes/dev/devflow/README.md
---

# README Improvement — Pretty, Professional, Accurate

## Context

The devflow README is the primary entry point for anyone discovering the project. It currently has solid content covering all 6 layers, commands, and design decisions — but the presentation is utilitarian. The brew install command also references a local formula path, which is confusing for someone who hasn't cloned the repo yet.

A polished README with modern structure, badges, and clear visual hierarchy will make the project look more professional and increase adoption. The [cortex-mem](https://github.com/sopaco/cortex-mem) project is a good reference for README structure: hero section, elevator pitch, feature highlights with visuals, structured quick start, ecosystem diagram, and clean section hierarchy.

## Problem Statement

1. **Broken install flow**: The Homebrew section says `brew install --formula Formula/devflow.rb` — this only works if you've already cloned the repo. First-time users need either a tap command or a clear "from source" disclaimer.
2. **Flat structure**: The README is a wall of tables and code blocks without visual hierarchy. No badges, no hero section, no expandable details for dense sections.
3. **No elevator pitch**: The opening line is functional but not compelling. There's no "What is devflow?" section that quickly communicates value.
4. **Missing architecture visual**: The 6-layer architecture would benefit from a mermaid diagram or similar visualization embedded in the README.

## Desired Outcome

A README that:

- Immediately communicates what devflow is and why it matters (hero + elevator pitch)
- Has correct, copy-pasteable install commands for all methods
- Uses modern GitHub README conventions (badges, collapsible sections, mermaid diagrams)
- Retains ALL existing content — nothing is removed, only restructured and enhanced
- Looks professional enough to share publicly

## Implementation Guide

### Step 1: Read Current README

Read `/Users/andrejorgelopes/dev/devflow/README.md` thoroughly. Catalog every piece of information so nothing is lost.

### Step 2: Analyze cortex-mem README for Style Patterns

Fetch `https://github.com/sopaco/cortex-mem` and note the structural patterns:

- Hero banner image (optional — devflow doesn't have one, skip this)
- Badges row (version, license, platform, build status)
- "What is X?" section — 2-3 sentence elevator pitch
- Feature highlights with emoji icons and brief descriptions
- Visual architecture diagram (mermaid flowchart)
- Collapsible `<details>` sections for dense content
- Clean quick start with numbered steps
- Modular ecosystem description
- Contributing section
- License footer

### Step 3: Fix Brew Install Command

Replace the current Homebrew section. Two options (implement both):

````markdown
### Homebrew (tap)

```bash
brew tap AndreJorgeLopes/devflow
brew install devflow
```
````

### From Source

```bash
git clone https://github.com/AndreJorgeLopes/devflow.git ~/dev/devflow
cd ~/dev/devflow
brew install --formula ./Formula/devflow.rb
# OR
make link  # symlinks to ~/.local/bin/devflow
```

````

### Step 4: Restructure the README

Proposed section order:

1. **Hero**: Project name + one-line tagline + badges (license, platform, version)
2. **What is devflow?**: 2-3 sentence elevator pitch. "Developer multiplier, not replacement."
3. **The 6 Layers** (visual): Mermaid diagram showing the layer stack, then the existing table
4. **Quick Start**: 3-4 commands to go from zero to running
5. **Installation**: All methods (curl, brew tap, from source) with prerequisites
6. **Commands Reference**: Existing command list, formatted as a table
7. **Skills Marketplace**: Existing skills table
8. **How `devflow init` Works**: Existing content, possibly in a `<details>` block
9. **Layer Deep Dives**: Collapsible sections for Hindsight, Docker, Continue.dev
10. **Project Structure**: Existing tree
11. **Design Decisions**: Existing bullet list
12. **Contributing**: Brief section (fork, branch, PR)
13. **License**: MIT

### Step 5: Add Mermaid Architecture Diagram

```mermaid
graph TB
    subgraph "devflow CLI"
        CLI[devflow]
    end

    subgraph "Layer 1: Memory"
        Hindsight[Hindsight MCP<br/>3-tier persistent memory]
    end

    subgraph "Layer 2: Session Management"
        AgentDeck[Agent Deck<br/>TUI + Conductor]
    end

    subgraph "Layer 3: Git Isolation"
        Worktrunk[Worktrunk<br/>Worktree lifecycle]
    end

    subgraph "Layer 4: Code Review"
        Continue[Continue.dev<br/>Pre-push checks]
    end

    subgraph "Layer 5: Process Discipline"
        Config[CLAUDE.md + Skills<br/>Agent configuration]
    end

    subgraph "Layer 6: Observability"
        Langfuse[Langfuse<br/>Tracing & costs]
    end

    CLI --> Hindsight
    CLI --> AgentDeck
    CLI --> Worktrunk
    CLI --> Continue
    CLI --> Config
    CLI --> Langfuse
````

### Step 6: Add Badges

```markdown
![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
![Shell: Bash](https://img.shields.io/badge/shell-bash-green.svg)
```

### Step 7: Review and Verify

- Confirm all original content is preserved
- Verify all links work
- Check mermaid renders on GitHub
- Ensure install commands are correct

## Acceptance Criteria

- [ ] Brew install command either uses `brew tap` or clearly states "requires cloning first"
- [ ] README has a hero section with project name, tagline, and badges
- [ ] "What is devflow?" elevator pitch section exists (2-3 sentences)
- [ ] Mermaid architecture diagram is embedded and renders on GitHub
- [ ] All 6 layers are described with their tools and purpose
- [ ] Quick start section has 3-4 copy-pasteable commands
- [ ] Dense sections (init details, layer deep dives) use collapsible `<details>` blocks
- [ ] Commands are presented in a scannable table format
- [ ] Skills marketplace table is preserved
- [ ] ALL original content is present — nothing removed
- [ ] Contributing section exists
- [ ] License section exists

## Technical Notes

- GitHub renders mermaid diagrams natively in markdown — no external service needed
- Use `<details><summary>` for collapsible sections to keep the README scannable
- Badge URLs use shields.io — no account needed, they're static
- The cortex-mem README uses images heavily; devflow doesn't have images, so rely on mermaid diagrams and structured text instead
- Keep the README under ~300 lines if possible by collapsing dense sections

## Verification

````bash
# Verify the README renders correctly
# Option 1: Push to a branch and check GitHub rendering
# Option 2: Use a local markdown previewer that supports mermaid
grip README.md  # if grip is installed

# Verify all links
# Manually click through badge URLs and GitHub links

# Verify mermaid renders
# GitHub natively renders ```mermaid blocks — push and check
````
