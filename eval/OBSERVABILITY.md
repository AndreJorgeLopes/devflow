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

### As built (v3 stack + OTel collector)

`docker/docker-compose.yml` now runs **Langfuse v3** (`langfuse/langfuse:3` web +
worker + ClickHouse + Redis + MinIO) plus an **OTel Collector**. Secrets live in
`docker/.env` (gitignored); the compose uses `${VAR:-dev-default}`.

Passive wiring (no per-session manual steps, works from terminal AND the desktop app):
```
Claude Code ── OTLP ──▶ otel-collector :4318 ── +Basic auth ──▶ langfuse-web /api/public/otel ──▶ ClickHouse
```
- `~/.claude/settings.json` `env` sets `CLAUDE_CODE_ENABLE_TELEMETRY=1`,
  `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`, `OTEL_TRACES_EXPORTER=otlp`,
  `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318`,
  + the `OTEL_LOG_*` content flags. **No secret in settings.json** — the collector
  ([docker/otel-collector-config.yaml](../docker/otel-collector-config.yaml)) holds
  the Basic-auth header, read from `docker/.env` (`LANGFUSE_OTEL_BASIC_AUTH`).
- Project + keys are seeded on a fresh DB via `LANGFUSE_INIT_*` (docker/.env), so the
  existing `pk-lf-…`/`sk-lf-…` keep working.
- `restart: unless-stopped` on every service → always-on across reboots.

### ⚠️ Known issues with Langfuse v3.202.1 self-host (as of this build)
Verified empirically; these are **langfuse-runtime**, not the compose:
1. **Public read API `/api/public/traces` + `/metrics` error** with
   `relation "observations_view" does not exist`. That view is intentionally DROPPED
   by migration `20250221143400_drop_trace_view_observation_view`, yet the compiled
   `pages/api/public/traces.js` still queries it → the web image's code is inconsistent
   with its own migrations. The **browser UI** (tRPC, ClickHouse-backed) may still work;
   verify at http://localhost:3100.
2. **OTLP ingestion is flaky on boot** — the `/api/public/otel` route 404s until a
   `docker compose restart langfuse-web`, and ingestion to ClickHouse has been
   intermittent (verified working at one point: traces reached ClickHouse via the
   collector; later boots needed a worker restart and sometimes still didn't persist).

**Reliable fallback that works today:** the score-push bridge over the **native**
ingestion API (which returns 207, unaffected by the above):
```bash
cd eval && npx -y promptfoo@latest eval --output results.json
bash lib/langfuse-push.sh results.json <version>   # uses /api/public/ingestion
```

**Recommendation:** treat **promptfoo as the primary, reliable** eval/observability
layer. Langfuse v3 OTLP passive tracing is wired but flaky on this version — if you
want it solid, pin/try a different `langfuse/langfuse` v3 tag, or rely on the
score-push bridge for version-over-version quality tracking.
