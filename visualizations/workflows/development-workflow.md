---
tags:
  [
    devflow,
    workflow,
    sdd,
    tdd,
    brainstorming,
    planning,
    code-review,
    merge-request,
    conductor,
  ]
related: ["[[devflow-ecosystem]]"]
---

# Development Workflow — From Idea to Merge Request

> The full SDD (Subagent-Driven Development) workflow using devflow's 6-layer toolchain.
> Related: [[devflow-ecosystem]]

---

## 1. High-Level Flow

```mermaid
%%{init: {'flowchart': {'rankSpacing': 50, 'nodeSpacing': 30, 'diagramPadding': 15}}}%%
graph TD
    START(["Feature request /<br/>Bug report"])
    WORKTREE["Developer at terminal:<br/>devflow worktree feat/X --agent claude<br/>(CLI creates worktree + launches session)"]
    SESSION(["Agent session starts<br/>in worktree"])
    RECALL["Recall from Hindsight<br/>recall('project: topic')"]
    BRAIN["Brainstorming<br/>(superpowers skill)"]
    PLAN["Writing Plans<br/>(superpowers skill)"]
    CHOOSE{"Execution<br/>approach?"}
    SDD["Subagent-Driven Dev<br/>(same session)"]
    EXEC["Executing Plans<br/>(parallel session)"]
    LOOP["TDD Implementation Loop<br/>(per task)"]
    VERIFY["Verification<br/>(superpowers skill)"]
    CHECK["Pre-Push Check<br/>devflow check + self-review"]
    COMMIT["Commit + Push"]
    MR["Create Merge Request<br/>gh pr create"]
    RETAIN["Retain learnings<br/>retain('project: discovery')"]
    CLEANUP["Worktree Cleanup<br/>(agent-offered: delete or keep)"]
    DONE(["Done"])

    COND["Conductor<br/>(parallel process)<br/>monitors all sessions"]

    START --> WORKTREE
    WORKTREE --> SESSION
    SESSION --> RECALL
    RECALL --> BRAIN
    BRAIN --> PLAN
    PLAN --> CHOOSE
    CHOOSE -->|"Same session"| SDD
    CHOOSE -->|"Separate session"| EXEC
    SDD --> LOOP
    EXEC --> LOOP
    LOOP --> VERIFY
    VERIFY --> CHECK
    CHECK --> COMMIT
    COMMIT --> MR
    MR --> RETAIN
    RETAIN --> CLEANUP
    CLEANUP --> DONE

    COND -.->|"monitors"| SESSION
    COND -.->|"auto-responds<br/>routine prompts"| LOOP
    COND -.->|"escalates to human<br/>during brainstorming"| BRAIN
    COND -.->|"escalates on<br/>repeated failures"| VERIFY

    classDef hindsightStyle fill:#7c3aed,color:#fff,stroke:#5b21b6
    classDef worktrunkStyle fill:#059669,color:#fff,stroke:#047857
    classDef skillsStyle fill:#be185d,color:#fff,stroke:#9d174d
    classDef reviewStyle fill:#d97706,color:#fff,stroke:#b45309
    classDef decisionStyle fill:#374151,color:#fff,stroke:#1f2937
    classDef terminalStyle fill:#6b7280,color:#fff,stroke:#4b5563
    classDef conductorStyle fill:#f59e0b,color:#fff,stroke:#d97706
    classDef agentDeckStyle fill:#3b82f6,color:#fff,stroke:#1e40af

    class RECALL,RETAIN hindsightStyle
    class WORKTREE,CLEANUP worktrunkStyle
    class BRAIN,PLAN,SDD,EXEC,LOOP,VERIFY skillsStyle
    class CHECK reviewStyle
    class MR,COMMIT reviewStyle
    class CHOOSE decisionStyle
    class START,DONE terminalStyle
    class SESSION agentDeckStyle
    class COND conductorStyle
```

---

## 2. Phase 1 — Brainstorming

> **Conductor note:** The Conductor escalates to the human during brainstorming — this phase is interactive and should not be auto-responded.

```mermaid
%%{init: {'flowchart': {'rankSpacing': 50, 'nodeSpacing': 30, 'diagramPadding': 15}}}%%
graph TD
    B_START(["Brainstorming skill invoked"])
    B_CTX["Explore project context<br/>(files, docs, recent commits)"]
    B_Q["Ask clarifying questions<br/>(one at a time, prefer multiple choice)"]
    B_APPROACH["Propose 2-3 approaches<br/>(with trade-offs + recommendation)"]
    B_DESIGN["Present design<br/>(section by section)"]
    B_OK{"User approves<br/>design?"}
    B_DOC["Write design doc<br/>docs/plans/YYYY-MM-DD-topic-design.md"]
    B_NEXT(["Invoke writing-plans skill"])

    B_START --> B_CTX
    B_CTX --> B_Q
    B_Q --> B_APPROACH
    B_APPROACH --> B_DESIGN
    B_DESIGN --> B_OK
    B_OK -->|"No, revise"| B_DESIGN
    B_OK -->|"Yes"| B_DOC
    B_DOC --> B_NEXT

    classDef skillsStyle fill:#be185d,color:#fff,stroke:#9d174d
    classDef decisionStyle fill:#374151,color:#fff,stroke:#1f2937
    classDef terminalStyle fill:#6b7280,color:#fff,stroke:#4b5563

    class B_CTX,B_Q,B_APPROACH,B_DESIGN,B_DOC skillsStyle
    class B_OK decisionStyle
    class B_START,B_NEXT terminalStyle
```

---

## 3. Phase 2 — Writing Plans

```mermaid
%%{init: {'flowchart': {'rankSpacing': 50, 'nodeSpacing': 30, 'diagramPadding': 15}}}%%
graph TD
    P_START(["Writing-plans skill invoked"])
    P_BREAK["Break design into<br/>bite-sized tasks (2-5 min each)"]
    P_STRUCT["Structure each task:<br/>files, test, implementation, command"]
    P_TDD["Embed TDD steps per task:<br/>1. Write failing test<br/>2. Verify fail<br/>3. Implement<br/>4. Verify pass<br/>5. Commit"]
    P_SAVE["Save plan to<br/>docs/plans/YYYY-MM-DD-feature.md"]
    P_CHOOSE{"Execution<br/>approach?"}
    P_SDD(["Subagent-Driven Dev<br/>(same session)"])
    P_EXEC(["Executing Plans<br/>(parallel session)"])

    P_START --> P_BREAK
    P_BREAK --> P_STRUCT
    P_STRUCT --> P_TDD
    P_TDD --> P_SAVE
    P_SAVE --> P_CHOOSE
    P_CHOOSE -->|"Subagent-Driven"| P_SDD
    P_CHOOSE -->|"Parallel Session"| P_EXEC

    classDef skillsStyle fill:#be185d,color:#fff,stroke:#9d174d
    classDef decisionStyle fill:#374151,color:#fff,stroke:#1f2937
    classDef terminalStyle fill:#6b7280,color:#fff,stroke:#4b5563

    class P_BREAK,P_STRUCT,P_TDD,P_SAVE skillsStyle
    class P_CHOOSE decisionStyle
    class P_START,P_SDD,P_EXEC terminalStyle
```

---

## 4. Phase 3 — TDD Implementation Loop (Per Task)

> **Conductor note:** The Conductor can auto-respond to routine prompts during this phase (e.g., confirming test runs, approving standard refactors). It escalates to the human when tests fail repeatedly.

```mermaid
%%{init: {'flowchart': {'rankSpacing': 50, 'nodeSpacing': 30, 'diagramPadding': 15}}}%%
graph TD
    T_START(["Task N from plan"])
    T_RED["RED: Write failing test<br/>(exact test from plan)"]
    T_RUN1["Run test<br/>Expected: FAIL"]
    T_FAIL{"Test<br/>fails?"}
    T_GREEN["GREEN: Write minimal<br/>implementation to pass"]
    T_RUN2["Run test<br/>Expected: PASS"]
    T_PASS{"Test<br/>passes?"}
    T_REFACTOR["REFACTOR: Clean up<br/>(no behavior change)"]
    T_RUN3["Run full test suite<br/>Expected: ALL PASS"]
    T_COMMIT["Commit<br/>(frequent, small commits)"]
    T_SPEC["Spec Review<br/>(does implementation match spec?)"]
    T_SPEC_OK{"Spec<br/>approved?"}
    T_QUALITY["Code Quality Review<br/>(dispatches code-reviewer)"]
    T_QUALITY_OK{"Quality<br/>approved?"}
    T_DONE(["Task complete"])

    T_START --> T_RED
    T_RED --> T_RUN1
    T_RUN1 --> T_FAIL
    T_FAIL -->|"No — fix test"| T_RED
    T_FAIL -->|"Yes"| T_GREEN
    T_GREEN --> T_RUN2
    T_RUN2 --> T_PASS
    T_PASS -->|"No — fix impl"| T_GREEN
    T_PASS -->|"Yes"| T_REFACTOR
    T_REFACTOR --> T_RUN3
    T_RUN3 --> T_COMMIT
    T_COMMIT --> T_SPEC
    T_SPEC --> T_SPEC_OK
    T_SPEC_OK -->|"No — fix issues"| T_GREEN
    T_SPEC_OK -->|"Yes"| T_QUALITY
    T_QUALITY --> T_QUALITY_OK
    T_QUALITY_OK -->|"No — fix issues"| T_REFACTOR
    T_QUALITY_OK -->|"Yes"| T_DONE

    classDef redStyle fill:#dc2626,color:#fff,stroke:#b91c1c
    classDef greenStyle fill:#059669,color:#fff,stroke:#047857
    classDef refactorStyle fill:#3b82f6,color:#fff,stroke:#1e40af
    classDef reviewStyle fill:#d97706,color:#fff,stroke:#b45309
    classDef decisionStyle fill:#374151,color:#fff,stroke:#1f2937
    classDef terminalStyle fill:#6b7280,color:#fff,stroke:#4b5563

    class T_RED,T_RUN1 redStyle
    class T_GREEN,T_RUN2 greenStyle
    class T_REFACTOR,T_RUN3,T_COMMIT refactorStyle
    class T_SPEC,T_QUALITY reviewStyle
    class T_FAIL,T_PASS,T_SPEC_OK,T_QUALITY_OK decisionStyle
    class T_START,T_DONE terminalStyle
```

---

## 5. Phase 4 — Finishing & Merge Request

This phase runs entirely inside the agent session: verification, devflow check, commit, visualization updates, PR description strategy, PR/MR creation, retain learnings, and optional worktree cleanup. Post-PR continuation is enforced by hooks (PostToolUse nudge + Stop hook PR detection + explicit skill instruction).

```mermaid
%%{init: {'flowchart': {'rankSpacing': 50, 'nodeSpacing': 30, 'diagramPadding': 15}}}%%
graph TD
    F_START(["All tasks complete"])

    subgraph AgentActions [" Agent Actions (inside session) "]
        F_VERIFY["Run full verification<br/>(tests, lint, build)"]
        F_PASS{"All<br/>pass?"}
        F_FIX["Fix failures"]
        F_CN["Pre-push check<br/>devflow check"]
        F_SELF["Self-review vs CLAUDE.md<br/>(naming, architecture, security)"]
        F_COMMIT["Commit changes"]
        F_VIZ{"Visualizations<br/>exist?"}
        F_VIZ_UPDATE["Check & update diagrams<br/>(analyze diff, propose updates)"]
        F_VIZ_COMMIT["Commit visualization updates"]
        F_PRSTRAT["Resolve PR description strategy<br/>(recall preference / ask user)"]
        F_CHECKPOINT["CHECKPOINT: Present diff<br/>(wait for user approval)"]
        F_PUSH["git push -u origin HEAD"]
        F_GH["Create PR/MR<br/>(gh pr create / glab mr create)"]
        F_RETAIN["Retain session learnings<br/>retain('project: ...')"]
        F_SUMMARY["Present feature summary"]
        F_CLEANUP_Q{"Worktree<br/>cleanup?"}
        F_DELETE["devflow done branch<br/>(delete worktree)"]
        F_KEEP["Keep for review feedback"]
    end

    F_DONE(["Done"])

    F_START --> F_VERIFY
    F_VERIFY --> F_PASS
    F_PASS -->|"No"| F_FIX
    F_FIX --> F_VERIFY
    F_PASS -->|"Yes"| F_CN
    F_CN --> F_SELF
    F_SELF --> F_COMMIT
    F_COMMIT --> F_VIZ
    F_VIZ -->|"No"| F_PRSTRAT
    F_VIZ -->|"Yes"| F_VIZ_UPDATE
    F_VIZ_UPDATE --> F_VIZ_COMMIT
    F_VIZ_COMMIT --> F_PRSTRAT
    F_PRSTRAT --> F_CHECKPOINT
    F_CHECKPOINT --> F_PUSH
    F_PUSH --> F_GH
    F_GH --> F_RETAIN
    F_RETAIN --> F_SUMMARY
    F_SUMMARY --> F_CLEANUP_Q
    F_CLEANUP_Q -->|"Delete now"| F_DELETE
    F_CLEANUP_Q -->|"Keep"| F_KEEP
    F_DELETE --> F_DONE
    F_KEEP --> F_DONE

    classDef verifyStyle fill:#059669,color:#fff,stroke:#047857
    classDef reviewStyle fill:#d97706,color:#fff,stroke:#b45309
    classDef hindsightStyle fill:#7c3aed,color:#fff,stroke:#5b21b6
    classDef langfuseStyle fill:#0891b2,color:#fff,stroke:#0e7490
    classDef worktrunkStyle fill:#059669,color:#fff,stroke:#047857
    classDef decisionStyle fill:#374151,color:#fff,stroke:#1f2937
    classDef terminalStyle fill:#6b7280,color:#fff,stroke:#4b5563
    classDef skillsStyle fill:#be185d,color:#fff,stroke:#9d174d

    class F_VERIFY,F_PASS,F_FIX verifyStyle
    class F_CN,F_SELF,F_PUSH,F_GH,F_COMMIT,F_CHECKPOINT reviewStyle
    class F_RETAIN hindsightStyle
    class F_SUMMARY langfuseStyle
    class F_DELETE,F_KEEP worktrunkStyle
    class F_PASS,F_VIZ,F_CLEANUP_Q decisionStyle
    class F_START,F_DONE terminalStyle
    class F_VIZ_UPDATE,F_VIZ_COMMIT,F_PRSTRAT skillsStyle
```

---

## 6. Tool Active at Each Phase

| Phase              |   Hindsight (L1)    | Agent Deck (L2) | Conductor (L2) |   Worktrunk (L3)   | Code Review (L4)  |  Skills (L5)   |  Langfuse (L6)  |
| ------------------ | :-----------------: | :-------------: | :------------: | :----------------: | :---------------: | :------------: | :-------------: |
| **Start (CLI)**    |          —          |  wraps session  |       —        |  create worktree   |         —         |       —        |        —        |
| **Recall (Agent)** |       recall        |        —        |    monitors    |         —          |         —         |       —        |     traces      |
| **Brainstorming**  |   recall context    |        —        |   escalates    |         —          |         —         | brainstorming  |     traces      |
| **Writing Plans**  |          —          |        —        |    monitors    |         —          |         —         | writing-plans  |     traces      |
| **TDD Loop**       | retain discoveries  |        —        | auto-responds  | isolated workspace |         —         |    TDD, SDD    |     traces      |
| **Spec Review**    |          —          |        —        | auto-responds  |         —          |         —         | spec-reviewer  |     traces      |
| **Quality Review** |          —          |        —        | auto-responds  |         —          |         —         | code-reviewer  |     traces      |
| **Pre-Push**       |          —          |        —        |    monitors    |         —          |  devflow check    | pre-push-check |     traces      |
| **Create MR**      | context for PR body |        —        |    monitors    |         —          |         —         |   create-pr    |     traces      |
| **Viz Check**      |          —          |        —        |    monitors    |         —          |         —         | finish-feature |        —        |
| **PR Strategy**    |  recall preference  |        —        |    monitors    |         —          |         —         | finish-feature |        —        |
| **Create MR**      | context for PR body |        —        |    monitors    |         —          |         —         | finish-feature |     traces      |
| **Finish (Agent)** |  retain learnings   |        —        |    monitors    |         —          |         —         | finish-feature | session-summary |
| **Cleanup (Agent)**|          —          |        —        |       —        |    devflow done    |         —         | finish-feature |        —        |

---

## 7. Entry Points

There are two ways to start a devflow development session:

### Recommended: `devflow worktree`

```bash
devflow worktree feat/X --agent claude
```

- Uses **worktrunk** under the hood for worktree creation
- Runs `wt step copy-ignored` to copy `.env`, `node_modules`, and other gitignored files
- Launches an agent-deck session in the new worktree
- Single command from idea to working agent session

### Alternative: `agent-deck add`

```bash
agent-deck add . -c claude --worktree feat/X -b
```

- Atomic command — creates worktree + session in one step
- Does **not** run `copy-ignored` (no `.env`, `node_modules` in new worktree)
- Useful when you don't need gitignored files (e.g., pure documentation work)
- `-b` flag runs session in background
