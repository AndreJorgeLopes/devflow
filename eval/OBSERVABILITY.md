# devflow Skill Observability

Two layers, decoupled:

1. **Eval (promptfoo)** — runs a skill headlessly, asserts on output, judges,
   compares versions. **This is the primary "is v2 better than v1" loop.** Works
   now, no external setup.
2. **Tracing (Langfuse)** — optional persistent run history. Blocked on manual
   setup (see below).

## 1. Eval harness (promptfoo) — WORKING

```bash
cd eval
npx -y promptfoo@latest eval        # run all tests
npx -y promptfoo@latest view        # visual side-by-side matrix in browser
```

- Provider `exec: bash lib/run-skill.sh` runs `claude --print '<invocation>'`
  with `CLAUDECODE=""` (so the nested claude can launch — claude-agent-sdk#573)
  and `--model haiku` (cheap; override with `SKILL_EVAL_MODEL`).
- Assertions: deterministic (`is-json`, `regex`, `contains`, `json-schema`,
  `javascript`) + LLM-judge (`llm-rubric`, `g-eval`).
- **Version compare (vN vs vN+1):** add a second provider that runs the prior
  skill version (e.g. a worktree checked out at the previous tag), give each a
  `label`; `view` renders them as side-by-side columns. Keep both as columns in
  ONE config — promptfoo's cross-run *saved* diff is weak (issue #1025).

Proven on first run: `resolve-repo` PASS; a raw-JSON test FAIL because the model
wraps output in ```json fences — a genuine determinism finding, exactly what the
audit targets.

## 2. Langfuse tracing — REQUIRES MANUAL SETUP (cannot be automated)

The running container is **`langfuse/langfuse:2`** (verified). Empirically:
- `POST /api/public/otel/v1/traces` → **404** — v2 has **no OTLP receiver**.
  Native Claude Code OTel-trace ingestion needs **Langfuse v3** (adds
  ClickHouse + Redis + MinIO — a 6-service stack).
- `POST /api/public/ingestion` → **401** — present, but needs project API keys
  that can ONLY be created in the web UI.

### Path A — lightweight, works on v2 today (recommended first)
Push promptfoo eval scores into Langfuse as traces+scores (no v3 needed):

1. Open http://localhost:3100 → create org + project → Settings → API Keys.
2. Export keys:
   ```bash
   export LANGFUSE_HOST=http://localhost:3100
   export LANGFUSE_PUBLIC_KEY=pk-lf-...
   export LANGFUSE_SECRET_KEY=sk-lf-...
   ```
3. `cd eval && npx -y promptfoo@latest eval --output results.json`
   then `bash lib/langfuse-push.sh results.json` (bridge script — pushes each
   test as a trace with a pass/fail score, so you can track score-per-version
   over time in the Langfuse UI).

### Path B — full Claude Code OTel traces (needs v3 upgrade)
1. Upgrade `docker/docker-compose.yml` to `langfuse/langfuse:3` + add ClickHouse,
   Redis, MinIO per Langfuse v3 self-host docs.
2. Create project + keys (UI), build the Basic-auth header from them.
3. Enable Claude Code telemetry (Langfuse OTLP is **HTTP-only**, no gRPC):
   ```bash
   export CLAUDE_CODE_ENABLE_TELEMETRY=1
   export CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1   # spans/traces
   export OTEL_TRACES_EXPORTER=otlp
   export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
   export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:3100/api/public/otel
   export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <base64(pk:sk)>"
   # content (off by default — needed for LLM-judge over real prompt/output):
   export OTEL_LOG_USER_PROMPTS=1 OTEL_LOG_TOOL_DETAILS=1 OTEL_LOG_TOOL_CONTENT=1
   ```
   Claude Code then emits `claude_code.skill_activated` events + `skill.name`
   span attributes — skill-level attribution with zero custom instrumentation.

**Recommendation:** Path A now (cheap, real value), Path B as a separate task
(`tasks/P3/SPIKE-telemetry-observability.md` already tracks this) when raw
trace history is wanted.
