---
title: Code Review Architecture — Multi-CLI Abstraction
tags: [code-review, architecture, devflow]
related: [devflow-ecosystem]
---

# Code Review Architecture — Multi-CLI Abstraction

> Layer 4 of the devflow stack — AI-powered code review using Claude Code (primary) or OpenCode (fallback).
> Replaces the Continue.dev (`cn check`) dependency with a portable multi-CLI dispatch layer.

---

## 1. CLI Dispatch Flow

How `devflow check` resolves which AI CLI to invoke:

```mermaid
%%{init: {'flowchart': {'rankSpacing': 50, 'nodeSpacing': 30, 'diagramPadding': 15}}}%%
flowchart TD
    START["devflow check"]
    ENV{"DEVFLOW_REVIEW_CLI\nenv var set?"}
    USE_OVERRIDE["Use override CLI\n(user-specified binary)"]
    DETECT_CLAUDE{"claude\non PATH?"}
    USE_CLAUDE["Dispatch to\nClaude Code"]
    DETECT_OC{"opencode\non PATH?"}
    USE_OC["Dispatch to\nOpenCode"]
    FAIL["Error: No review CLI found\nInstall claude or opencode"]

    START --> ENV
    ENV -->|"yes"| USE_OVERRIDE
    ENV -->|"no"| DETECT_CLAUDE
    DETECT_CLAUDE -->|"found"| USE_CLAUDE
    DETECT_CLAUDE -->|"not found"| DETECT_OC
    DETECT_OC -->|"found"| USE_OC
    DETECT_OC -->|"not found"| FAIL

    classDef reviewStyle fill:#d97706,color:#fff,stroke:#b45309
    classDef cliStyle fill:#374151,color:#fff,stroke:#1f2937
    classDef errorStyle fill:#dc2626,color:#fff,stroke:#991b1b

    class START cliStyle
    class ENV,DETECT_CLAUDE,DETECT_OC reviewStyle
    class USE_OVERRIDE,USE_CLAUDE,USE_OC cliStyle
    class FAIL errorStyle
```

---

## 2. Check Rules Pipeline

Data flow from check rule files through each CLI backend to structured output:

```mermaid
%%{init: {'flowchart': {'rankSpacing': 50, 'nodeSpacing': 30, 'diagramPadding': 15}}}%%
flowchart TD
    subgraph Input [" Input Collection "]
        RULES[".devflow/checks/*.md\n(rule files)"]
        DIFF["git diff\n(staged or branch diff)"]
        RULES --> CONCAT["Concatenate rules\ninto single prompt"]
    end

    CONCAT --> DISPATCH{"CLI dispatch\n(from Step 1)"}
    DIFF --> DISPATCH

    subgraph Claude [" Claude Code Path "]
        CC_SYS["--system-prompt\n(concatenated rules)"]
        CC_STDIN["stdin\n(piped diff)"]
        CC_FLAGS["--permission-mode plan\n--allowed-tools\n'Read,Glob,Grep'"]
        CC_SCHEMA["--json-schema\n(optional structured output)"]
        CC_EXEC["claude"]
        CC_SYS --> CC_EXEC
        CC_STDIN --> CC_EXEC
        CC_FLAGS --> CC_EXEC
        CC_SCHEMA --> CC_EXEC
    end

    subgraph OpenCode [" OpenCode Path "]
        OC_PROMPT["Combined prompt\n(rules + diff in body)"]
        OC_FLAGS["opencode run\n--format default"]
        OC_PARSE["Parse text output\n(extract findings)"]
        OC_PROMPT --> OC_FLAGS
        OC_FLAGS --> OC_PARSE
    end

    DISPATCH -->|"claude"| CC_SYS
    DISPATCH -->|"claude"| CC_STDIN
    DISPATCH -->|"opencode"| OC_PROMPT

    CC_EXEC --> OUTPUT["Review Output\n(findings, suggestions,\npass/fail verdict)"]
    OC_PARSE --> OUTPUT

    classDef reviewStyle fill:#d97706,color:#fff,stroke:#b45309
    classDef cliStyle fill:#374151,color:#fff,stroke:#1f2937
    classDef inputStyle fill:#6b7280,color:#fff,stroke:#4b5563

    class RULES,DIFF,CONCAT inputStyle
    class DISPATCH reviewStyle
    class CC_SYS,CC_STDIN,CC_FLAGS,CC_SCHEMA,CC_EXEC cliStyle
    class OC_PROMPT,OC_FLAGS,OC_PARSE cliStyle
    class OUTPUT reviewStyle
```

---

## 3. Integration Points

Skills and commands that trigger `devflow check` as part of their workflow:

```mermaid
%%{init: {'flowchart': {'rankSpacing': 50, 'nodeSpacing': 30, 'diagramPadding': 15}}}%%
flowchart TD
    subgraph DirectInvocation [" Direct CLI "]
        DIRECT["devflow check\n(manual invocation)"]
    end

    subgraph Skills [" Skills (Process Discipline) "]
        PREPUSH["/pre-push-check\n(before git push)"]
        CREATEPR["/create-pr\n(during PR pipeline)"]
        FINISH["/finish-feature\n(feature completion)"]
    end

    CHECK["devflow check\n(dispatch layer)"]
    CLI["Resolved CLI\n(claude / opencode)"]
    RESULT["Review Result\n(pass / fail + findings)"]

    DIRECT --> CHECK
    PREPUSH -->|"self-review +\ncheck rules"| CHECK
    CREATEPR -->|"check before\ngh pr create"| CHECK
    FINISH -->|"final quality\ngate"| CHECK

    CHECK --> CLI
    CLI --> RESULT

    RESULT -->|"pass"| CONTINUE["Continue workflow\n(push / PR / merge)"]
    RESULT -->|"fail"| BLOCK["Block + show findings\n(fix before proceeding)"]

    classDef reviewStyle fill:#d97706,color:#fff,stroke:#b45309
    classDef skillsStyle fill:#be185d,color:#fff,stroke:#9d174d
    classDef cliStyle fill:#374151,color:#fff,stroke:#1f2937
    classDef passStyle fill:#059669,color:#fff,stroke:#047857
    classDef failStyle fill:#dc2626,color:#fff,stroke:#991b1b

    class DIRECT cliStyle
    class PREPUSH,CREATEPR,FINISH skillsStyle
    class CHECK,RESULT reviewStyle
    class CLI cliStyle
    class CONTINUE passStyle
    class BLOCK failStyle
```

---

## Notes

- **Why multi-CLI?** Continue.dev (`cn check`) was a single point of failure and required a separate npm dependency. The new dispatch layer uses whichever AI CLI is already installed.
- **Rule files** live in `.devflow/checks/*.md` (migrated from `.continue/checks/*.md`). Each file is a self-contained review rule with criteria and examples.
- **Structured output** via `--json-schema` is optional — when provided, Claude Code returns machine-parseable results for CI integration.
- **Fallback order** is deterministic: env override > claude > opencode. No interactive prompts during dispatch.
