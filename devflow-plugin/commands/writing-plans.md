---
description: [devflow v0.1.0] Write an implementation plan — extends superpowers:writing-plans with agent-deck parallel session handoff.
---

Use the `superpowers:writing-plans` skill to create the implementation plan.

After the plan is written, **read and follow** the devflow execution handoff extension.

**Step 0: Resolve devflow root.** Run this command and capture its output:

```bash
devflow root 2>/dev/null || readlink -f ~/.claude/commands/devflow | sed 's|/devflow-plugin/commands$||'
```

Store the result as DEVFLOW_ROOT. Then use the Read tool to load:

```
<DEVFLOW_ROOT>/skills/superpowers-wrappers/writing-plans.md
```

This file contains the agent-deck parallel session handoff instructions that extend the superpowers execution handoff with auto-launch support.

**IMPORTANT:** You MUST use the Read tool to load this file before proceeding with the execution handoff. Do not skip this step or try to guess the content.

$ARGUMENTS
