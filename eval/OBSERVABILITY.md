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

### ✅ Working — verified end-to-end
A trace pushed to the collector lands in ClickHouse AND is returned by the read API:
`otel=200`, `read=200`, ClickHouse + `/api/public/traces` both show it. Images pinned
to **`langfuse/langfuse:3.200.0`** (web + worker, identical).

### Hard-won gotchas (do NOT regress)
1. **Inline the shared env on `langfuse-web` — do NOT use the `<<: *langfuse-env`
   merge.** Docker Compose silently dropped the merged vars (incl. `CLICKHOUSE_URL`)
   from web when mixed with explicit keys + `${}` interpolation. Without
   `CLICKHOUSE_URL`, web falls back to the legacy postgres `observations_view` (DROPPED
   in v3 by migration `20250221…`) → every read 500s. That single missing var caused
   ALL the "observations_view does not exist" + no-data symptoms — NOT a version bug.
2. **Project-name collision.** The main repo `~/dev/devflow/docker/` (original
   `langfuse:2` compose) and a worktree `docker/` both default to compose project
   **`docker`** → docker mixes their containers. Run compose with an explicit
   `-f <path> --project-directory <path>`, and once this branch merges to main the
   main compose IS v3 so the collision disappears.
3. **Recreate-rename race.** `docker compose up`/`restart` on `langfuse-web` (it has
   `container_name` + `depends_on: service_healthy`) can fail with
   `No such container <hash>_devflow-langfuse-web`, leaving the OLD container serving
   stale env. Fix: a **full `down` then fresh `up`** (a fresh CREATE has no rename), not
   a partial recreate.

### Score-push bridge (feeds `devflow trace-review`'s score column)
Push a skill's quality score as a `devflow-eval` trace so trace-review can key it by
skill + timestamp (a per-skill-version score has no production trace id to join to):
```bash
# promptfoo pass-rate (varies only if the skill's config has a quality/judge assert)
cd eval && npx -y promptfoo@latest eval --output results.json
bash lib/langfuse-push.sh results.json <skill> [version]   # tags devflow-eval + skill:<name>

# tessl review score (varies with real quality — the signal that makes score-down meaningful)
score=$(tessl review run --workspace <ws> --json | python3 -c 'import sys,json;print(json.load(sys.stdin)["review"]["reviewScore"])')
bash lib/tessl-push.sh <skill> "$score" [version]          # normalises 0..100 -> 0..1
```
Both stamp `devflow-eval` + `skill:<name>` + metadata.skill_name; trace-review excludes
those eval traces from production cost/latency aggregation and only uses their scores.

**Recommendation:** promptfoo stays the primary deterministic eval gate; push the tessl
review score for the trace-review quality trend (shape-only promptfoo asserts sit at 1.0
and never flag). Langfuse gives passive run-history + the UI. Browse at http://localhost:3100.
