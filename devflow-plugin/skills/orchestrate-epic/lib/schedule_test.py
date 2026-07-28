#!/usr/bin/env python3
"""Behavioral tests for schedule.py — the deterministic core of orchestrate-epic.

Pure stdlib, no framework. Run: python3 schedule_test.py  (exit 0 = all pass).
Fixtures mirror the real MES-4414 WhatsApp-tags graph, which is why this doubles
as the skill's regression guard: the tag tickets had EMPTY Jira issuelinks, so a
links-only scheduler would produce a zero-edge graph — these tests lock in that
the edges (fed from the "Dependencies:" text) drive the waves correctly.
"""
import json
import subprocess
import sys
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SCHEDULE = os.path.join(HERE, "schedule.py")

TAGS = {
    "me": "andre.lopes@aircall.io",
    "tickets": [
        {"key": "MES-4415", "assignee": "andre.lopes@aircall.io", "status": "In Progress", "statusCategory": "indeterminate", "blockedBy": []},
        {"key": "MES-4459", "assignee": "andre.lopes@aircall.io", "status": "To Do", "statusCategory": "new", "blockedBy": ["MES-4415"]},
        {"key": "MES-4460", "assignee": "andre.lopes@aircall.io", "status": "To Do", "statusCategory": "new", "blockedBy": ["MES-4415", "MES-4459"]},
        {"key": "MES-4422", "assignee": "andre.lopes@aircall.io", "status": "To Do", "statusCategory": "new", "blockedBy": ["MES-4415"]},
        {"key": "MES-4461", "assignee": "andre.lopes@aircall.io", "status": "To Do", "statusCategory": "new", "blockedBy": ["MES-4459"]},
        {"key": "MES-4462", "assignee": "andre.lopes@aircall.io", "status": "To Do", "statusCategory": "new", "blockedBy": ["MES-4460"]},
        {"key": "MES-4463", "assignee": "andre.lopes@aircall.io", "status": "To Do", "statusCategory": "new", "blockedBy": ["MES-4422"]},
        {"key": "MES-4420", "assignee": "andre.lopes@aircall.io", "status": "To Do", "statusCategory": "new", "blockedBy": ["MES-4461"]},
        {"key": "MES-4421", "assignee": "andre.lopes@aircall.io", "status": "To Do", "statusCategory": "new", "blockedBy": ["MES-4462", "MES-4461"]},
    ],
}


def run(payload):
    p = subprocess.run([sys.executable, SCHEDULE], input=json.dumps(payload),
                       capture_output=True, text=True)
    out = json.loads(p.stdout) if p.stdout.strip() else {}
    return p.returncode, out


def clone(**over):
    d = json.loads(json.dumps(TAGS))
    d.update(over)
    return d


FAILS = []


def check(name, cond):
    print(("PASS" if cond else "FAIL") + " " + name)
    if not cond:
        FAILS.append(name)


# 1. Clean DAG: exit 0, 5 waves, correct roots/leaves, critical-path length 5.
code, o = run(TAGS)
check("clean graph exits 0", code == 0 and o.get("abstain") is False)
check("wave 0 is the data model only", o["waves"][0] == ["MES-4415"])
check("wave 1 is 4422 + 4459", o["waves"][1] == ["MES-4422", "MES-4459"])
check("5 waves (critical path length 5)", len(o["waves"]) == 5)
check("4421 is the deepest node", o["levels"]["MES-4421"] == 4)
check("nothing workable but the root (root In Progress, not resolved)",
      o["workable_now"] == ["MES-4415"])

# 2. Signalling the root done promotes exactly its direct dependents.
code, o = run(clone(done_signals=["MES-4415"]))
check("root done -> 4422 + 4459 workable", o["workable_now"] == ["MES-4422", "MES-4459"])

# 3. A dependency cycle abstains (exit 10) rather than inventing an order.
code, o = run({"me": None, "tickets": [
    {"key": "A", "assignee": None, "status": "To Do", "statusCategory": "new", "blockedBy": ["B"]},
    {"key": "B", "assignee": None, "status": "To Do", "statusCategory": "new", "blockedBy": ["A"]},
]})
check("cycle abstains with exit 10", code == 10 and o.get("abstain") is True)

# 4. Eligibility rule: mine+ToDo in; others' out; unassigned+InProgress out; resolved out.
code, o = run({"me": "me@x.com", "tickets": [
    {"key": "MINE", "assignee": "me@x.com", "status": "To Do", "statusCategory": "new", "blockedBy": []},
    {"key": "OTHER", "assignee": "bob@x.com", "status": "To Do", "statusCategory": "new", "blockedBy": []},
    {"key": "UNASSIGNED_IP", "assignee": None, "status": "In Progress", "statusCategory": "indeterminate", "blockedBy": []},
    {"key": "DONE", "assignee": "me@x.com", "status": "Done", "statusCategory": "done", "blockedBy": []},
]})
check("only mine+ToDo is eligible", o["eligible"] == ["MINE"])
reasons = {i["key"]: i["reason"] for i in o["ineligible"]}
check("others'-assigned excluded", reasons.get("OTHER") == "assigned to someone else")
check("unassigned+InProgress excluded", reasons.get("UNASSIGNED_IP") == "unassigned but not in To Do")
check("resolved excluded", "resolved" in reasons.get("DONE", ""))

# 5. Malformed input is a hard error (exit 1), not a silent wrong answer.
p = subprocess.run([sys.executable, SCHEDULE], input="{not json", capture_output=True, text=True)
check("malformed input exits 1", p.returncode == 1)

# 6. External blocker (key outside the set) blocks until signalled done, and is flagged.
code, o = run({"me": "me@x.com", "tickets": [
    {"key": "T", "assignee": "me@x.com", "status": "To Do", "statusCategory": "new", "blockedBy": ["EXT-1"]},
]})
check("external blocker keeps ticket blocked", o["workable_now"] == [] and "EXT-1" in o["external_blockers"].get("T", []))

print()
if FAILS:
    print("%d FAILED: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("all schedule.py behavior tests passed")
