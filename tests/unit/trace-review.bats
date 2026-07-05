#!/usr/bin/env bats
# tests/unit/trace-review.bats - Unit tests for the trace-review provider seam,
# scheduler dispatch, and the deterministic aggregation + regression math in
# lib/trace-review.py. All tests are network-free (no Langfuse required).

setup() {
  load '../helpers/common'
  _common_setup
  load '../helpers/mocks'
  load '../helpers/assertions'
  source_lib utils.sh
  source_lib trace-review.sh
  export ENGINE="${DEVFLOW_ROOT:-$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)}/lib/trace-review.py"
}

teardown() {
  _common_teardown
}

# ── detect_agent_provider (extensibility seam) ──

@test "detect_agent_provider honors DEVFLOW_AGENT override" {
  DEVFLOW_AGENT="opencode" run detect_agent_provider
  assert_success
  assert_output "opencode"
}

@test "detect_agent_provider can be forced to an arbitrary future provider" {
  DEVFLOW_AGENT="codex" run detect_agent_provider
  assert_output "codex"
}

# ── agent_invoke_cmd (provider-specific headless command) ──

@test "agent_invoke_cmd claude-code clears CLAUDECODE and uses claude --print" {
  DEVFLOW_AGENT="claude-code" run agent_invoke_cmd '/devflow:trace-review run'
  assert_success
  assert_output --partial 'CLAUDECODE='
  assert_output --partial 'claude --print'
}

@test "agent_invoke_cmd opencode uses opencode run (no native scheduler path)" {
  DEVFLOW_AGENT="opencode" run agent_invoke_cmd '/devflow:trace-review run'
  assert_output --partial 'opencode run'
}

# ── subcommand + scheduler dispatch ──

@test "devflow_trace_review rejects an unknown subcommand" {
  run devflow_trace_review bogus-sub
  assert_failure
  assert_output --partial 'Unknown trace-review subcommand'
}

@test "schedule rejects an unknown backend and points at the extension seam" {
  run _trace_review_schedule --backend bogus
  assert_failure
  assert_output --partial 'Unknown scheduler backend'
  assert_output --partial 'detect_agent_provider'
}

@test "schedule --backend claude emits a routine spec without touching crontab" {
  DEVFLOW_AGENT="claude-code" run _trace_review_schedule --backend claude --cron "0 9 * * 1"
  assert_success
  assert_output --partial 'devflow-trace-review-weekly'
  assert_output --partial '0 9 * * 1'
}

# ── deterministic regression math (pure functions, no network) ──

@test "engine flags cost regression beyond +25% threshold" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
this = {'s': {'count': 10, 'error_rate': 0.0, 'cost': 2.0, 'p95_latency': 1.0, 'mean_score': None}}
last = {'s': {'count': 10, 'error_rate': 0.0, 'cost': 1.0, 'p95_latency': 1.0, 'mean_score': None}}
rows = m._flag_regressions(this, last)
r = rows[0]
assert r['severity'] == 'HIGH', r['severity']
assert any('cost +100%' in f for f in r['flags']), r['flags']
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "engine does NOT flag a skill with no prior-week baseline (NEW, no false positive)" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
this = {'s': {'count': 5, 'error_rate': 1.0, 'cost': 99.0, 'p95_latency': 9.0, 'mean_score': 0.1}}
last = {}
rows = m._flag_regressions(this, last)
r = rows[0]
assert r['severity'] == 'NEW', r['severity']
assert r['flags'] == [], r['flags']
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "engine flags error-rate up beyond +10pp" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
this = {'s': {'count': 10, 'exec_total': 100, 'error_rate': 0.20, 'cost': 1.0, 'p95_latency': 1.0, 'mean_score': None}}
last = {'s': {'count': 10, 'exec_total': 100, 'error_rate': 0.05, 'cost': 1.0, 'p95_latency': 1.0, 'mean_score': None}}
r = m._flag_regressions(this, last)[0]
assert r['severity'] == 'HIGH', r['severity']
assert any('error rate +15pp' in f for f in r['flags']), r['flags']
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "engine flags score down beyond -0.05" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
this = {'s': {'count': 10, 'exec_total': 10, 'error_rate': 0.0, 'cost': 1.0, 'p95_latency': 1.0, 'mean_score': 0.70}}
last = {'s': {'count': 10, 'exec_total': 10, 'error_rate': 0.0, 'cost': 1.0, 'p95_latency': 1.0, 'mean_score': 0.90}}
r = m._flag_regressions(this, last)[0]
assert any('score -0.20' in f for f in r['flags']), r['flags']
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "engine flags p95 latency up beyond +25%" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
this = {'s': {'count': 10, 'exec_total': 10, 'error_rate': 0.0, 'cost': 1.0, 'p95_latency': 2.0, 'mean_score': None}}
last = {'s': {'count': 10, 'exec_total': 10, 'error_rate': 0.0, 'cost': 1.0, 'p95_latency': 1.0, 'mean_score': None}}
r = m._flag_regressions(this, last)[0]
assert any('p95 latency +100%' in f for f in r['flags']), r['flags']
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "engine marks CRITICAL when 2+ metrics regress" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
this = {'s': {'count': 10, 'exec_total': 100, 'error_rate': 0.30, 'cost': 2.0, 'p95_latency': 1.0, 'mean_score': None}}
last = {'s': {'count': 10, 'exec_total': 100, 'error_rate': 0.05, 'cost': 1.0, 'p95_latency': 1.0, 'mean_score': None}}
r = m._flag_regressions(this, last)[0]
assert r['severity'] == 'CRITICAL', r['severity']
assert len(r['flags']) >= 2, r['flags']
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "engine marks a skill GONE when it vanished this week" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
this = {}
last = {'s': {'count': 5, 'exec_total': 5, 'error_rate': 0.0, 'cost': 1.0, 'p95_latency': 1.0, 'mean_score': 0.9}}
r = m._flag_regressions(this, last)[0]
assert r['severity'] == 'GONE', r['severity']
assert r['flags'] == [], r['flags']
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "engine percentile is nearest-rank with pinned values" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
vals = [1,2,3,4,5,6,7,8,9,10]
# nearest-rank on 0-based index: p50 -> round(0.5*9)=4 -> vals[4]=5; p95 -> round(0.95*9)=9 -> vals[10th]=10
assert m._pct(vals, 50) == 5, m._pct(vals, 50)
assert m._pct(vals, 95) == 10, m._pct(vals, 95)
assert m._pct(vals, 0) == 1, m._pct(vals, 0)
assert m._pct([], 95) is None
assert m._pct([42], 95) == 42
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

# ── core aggregation pipeline (join + attribution + anti-inflation), the functions
#    the module docstring names as its reason to exist ──

@test "_attribute_traces rung 1: attributes a trace by the first skill_name span" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
# skill_name lands on claude_code.tool (NOT .execution); scan finds it wherever it sits
traces = [{'id': 't1'}, {'id': 't2'}]
obs_by_trace = {'t1': [
  {'name': 'claude_code.tool.execution', 'metadata': {'attributes': {}}},
  {'name': 'claude_code.tool', 'metadata': {'attributes': {'skill_name': 'devflow:review'}}},
], 't2': [{'name': 'claude_code.tool.execution', 'metadata': {'attributes': {}}}]}
skill, src = m._attribute_traces(traces, obs_by_trace, {})
assert skill == {'t1': 'devflow:review'}, skill   # t2 unmatched -> (unattributed) later
assert src == {'t1': 'skill_name'}, src
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "_attribute_traces rung 2: recovers a skill from a leading-slash user_prompt" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
traces = [{'id': 't1'}]
obs_by_trace = {'t1': [
  {'name': 'claude_code.interaction', 'metadata': {'attributes': {'user_prompt': '/devflow:review run --json'}}},
]}
skill, src = m._attribute_traces(traces, obs_by_trace, {})
assert skill == {'t1': 'devflow:review'}, skill   # first token, slash stripped
assert src == {'t1': 'slash_command'}, src
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "_attribute_traces rung 1 beats rung 2 (skill_name wins over slash_command)" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
traces = [{'id': 't1'}]
obs_by_trace = {'t1': [
  {'name': 'claude_code.interaction', 'metadata': {'attributes': {'user_prompt': '/some-alias'}}},
  {'name': 'claude_code.tool', 'metadata': {'attributes': {'skill_name': 'devflow:review'}}},
]}
skill, src = m._attribute_traces(traces, obs_by_trace, {})
assert skill == {'t1': 'devflow:review'}, skill
assert src == {'t1': 'skill_name'}, src
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "_attribute_traces rung 3: sidecar join binds each trace to the LATEST skill <= its ts (multi-skill session)" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
# One session, two skills invoked at different times; three interaction-grained traces.
# t_a (09:05) after skillA(09:00); t_b (10:05) after skillB(10:00); t_early (08:00) before any.
sidecar = m._load_sidecar  # sanity: symbol exists
sc = {'S1': [
  (m._parse_ts('2026-01-01T09:00:00Z'), 'skillA'),
  (m._parse_ts('2026-01-01T10:00:00Z'), 'skillB'),
]}
traces = [
  {'id': 't_early', 'sessionId': 'S1', 'timestamp': '2026-01-01T08:00:00Z'},
  {'id': 't_a',     'sessionId': 'S1', 'timestamp': '2026-01-01T09:05:00Z'},
  {'id': 't_b',     'sessionId': 'S1', 'timestamp': '2026-01-01T10:05:00Z'},
  {'id': 't_other', 'sessionId': 'S2', 'timestamp': '2026-01-01T10:05:00Z'},  # no sidecar rows
]
skill, src = m._attribute_traces(traces, {}, sc)
assert 't_early' not in skill, skill      # before first invocation -> unattributed
assert skill['t_a'] == 'skillA', skill    # not skillB (that is later)
assert skill['t_b'] == 'skillB', skill
assert 't_other' not in skill, skill
assert src['t_a'] == 'hook_sidecar', src
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

# ── enrichment hook (WRITE side of rung 3) ──

@test "skill-activation-log hook writes a row only for the Skill tool" {
  local hook="${DEVFLOW_ROOT:-$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)}/lib/hooks/skill-activation-log.sh"
  export TRACE_REVIEW_SIDECAR="${BATS_TEST_TMPDIR}/sidecar.jsonl"
  rm -f "$TRACE_REVIEW_SIDECAR"
  echo '{"session_id":"S1","tool_name":"Skill","tool_input":{"skill":"devflow:review"}}' | bash "$hook"
  echo '{"session_id":"S1","tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$hook"
  echo 'not json at all' | bash "$hook"
  run bash -c "wc -l < '$TRACE_REVIEW_SIDECAR' | tr -d ' '"
  assert_output "1"                                  # only the Skill invocation logged
  run cat "$TRACE_REVIEW_SIDECAR"
  assert_output --partial '"skill": "devflow:review"'
  assert_output --partial '"session_id": "S1"'
}

@test "skill-activation-log hook never fails the tool call (exit 0) on bad payload" {
  local hook="${DEVFLOW_ROOT:-$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)}/lib/hooks/skill-activation-log.sh"
  export TRACE_REVIEW_SIDECAR="${BATS_TEST_TMPDIR}/sidecar2.jsonl"
  run bash -c "echo 'garbage{' | bash '$hook'"
  assert_success                                     # exit 0 even when parsing fails
}

@test "_load_sidecar skips malformed lines and returns sorted per-session entries" {
  run python3 -c "
import importlib.util, os, tempfile
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
p = tempfile.mktemp()
open(p,'w').write(
  '{\"session_id\":\"S1\",\"ts\":\"2026-01-01T10:00:00Z\",\"skill\":\"late\"}\n'
  '{\"session_id\":\"S1\",\"ts\":\"2026-01-01T09:00:00Z\",\"skill\":\"early\"}\n'
  'not-json-truncated-tail\n'
  '{\"session_id\":\"S1\",\"skill\":\"no-ts-dropped\"}\n')
sc = m._load_sidecar(p)
os.unlink(p)
assert [s for _,s in sc['S1']] == ['early','late'], sc   # sorted by ts; no-ts row dropped; junk skipped
assert m._load_sidecar('/nonexistent/path') == {}
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "_trace_exec_stats counts executions only and never counts a permission reject as an error" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
obs_by_trace = {'t1': [
  {'name': 'claude_code.tool.execution', 'level': 'ERROR', 'metadata': {'attributes': {'success': 'false'}}},
  {'name': 'claude_code.tool.blocked_on_user', 'metadata': {'attributes': {'decision': 'reject'}}},
  {'name': 'claude_code.tool.execution', 'metadata': {'attributes': {'success': 'true'}}},
]}
total, failed = m._trace_exec_stats('t1', obs_by_trace)
assert (total, failed) == (2, 1), (total, failed)   # reject is not an execution; error_rate = 1/2 not 1/3 or 2/3
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "_aggregate joins by traceId, uses per-trace totalCost/latency, and counts unattributed traces" {
  run python3 -c "
import importlib.util, os
from datetime import datetime, timezone
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
lo = datetime(2026,1,1,tzinfo=timezone.utc); hi = datetime(2026,1,8,tzinfo=timezone.utc)
traces = [
  {'id': 't1', 'timestamp': '2026-01-02T00:00:00Z', 'totalCost': 2.0, 'latency': 5.0},
  {'id': 't2', 'timestamp': '2026-01-03T00:00:00Z', 'totalCost': 0.5, 'latency': 9.0},  # no skill -> unattributed
  {'id': 't3', 'timestamp': '2025-12-31T00:00:00Z', 'totalCost': 99.0, 'latency': 1.0}, # out of window
]
obs_by_trace = {'t1': [{'name': 'claude_code.tool.execution', 'metadata': {'attributes': {'success': 'true'}}}]}
trace_skill = {'t1': 'devflow:review'}
agg = m._aggregate(traces, obs_by_trace, trace_skill, {}, lo, hi)
assert agg['devflow:review']['count'] == 1, agg
assert agg['devflow:review']['cost'] == 2.0, agg          # per-trace totalCost passthrough, not summed spans
assert agg['devflow:review']['p95_latency'] == 5.0, agg
assert agg[m.UNATTRIBUTED]['count'] == 1, agg             # t2 bucketed as unattributed
assert 't3' not in [x for x in agg], 'out-of-window trace leaked'
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}

@test "_flag_regressions holds (unattributed) OUT of the per-skill ranking" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
this = {'devflow:review': {'count': 3, 'exec_total': 3, 'error_rate': 0.0, 'cost': 1.0, 'p95_latency': 1.0, 'mean_score': None},
        m.UNATTRIBUTED: {'count': 99, 'exec_total': 99, 'error_rate': 0.0, 'cost': 500.0, 'p95_latency': 300.0, 'mean_score': None}}
rows = m._flag_regressions(this, {})
skills = [r['skill'] for r in rows]
assert m.UNATTRIBUTED not in skills, skills   # never ranked as a skill
assert skills == ['devflow:review'], skills
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}
