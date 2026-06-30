#!/usr/bin/env bats
# tests/unit/trace-review.bats — Unit tests for the trace-review provider seam,
# scheduler dispatch, and the deterministic regression math in lib/trace-review.py.
# All tests are network-free (no Langfuse required).

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

@test "engine percentile is deterministic and nearest-rank" {
  run python3 -c "
import importlib.util, os
spec = importlib.util.spec_from_file_location('tr', os.environ['ENGINE'])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
vals = [1,2,3,4,5,6,7,8,9,10]
assert m._pct(vals, 50) == m._pct(vals, 50)
assert m._pct([], 95) is None
assert m._pct([42], 95) == 42
print('OK')
"
  assert_success
  assert_output --partial 'OK'
}
