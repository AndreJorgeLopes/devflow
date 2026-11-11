#!/usr/bin/env python3
"""Behavioral tests for gate.py (mode, merge-gate detection, pre-merge check).

Pure stdlib, no framework. Run: python3 gate_test.py  (exit 0 = all pass).
The premerge fixtures mirror the signal-copier gate: an approval names the head SHA,
and a commit that lands after the approval makes it stale.
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "gate.py")
HEAD = "8e7d6b5a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f"
OLD = "3f2a1c0"
FAILS = []


def run(*args, stdin=""):
    p = subprocess.run([sys.executable, GATE, *args], input=stdin, capture_output=True, text=True)
    return p.returncode, (json.loads(p.stdout) if p.stdout.strip() else {})


def check(name, cond):
    if not cond:
        FAILS.append(name)
        print("FAIL", name)


def pr(comments, checks=None, state="OPEN", mss="CLEAN"):
    if checks is None:
        checks = [{"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SUCCESS"}]
    return json.dumps({"number": 51, "state": state, "headRefOid": HEAD, "mergeStateStatus": mss,
                       "statusCheckRollup": checks, "comments": comments})


def c(body, at):
    return {"body": body, "createdAt": at}


# mode
code, o = run("mode", "https://github.com/AndreJorgeLopes/signal-copier/issues/12")
check("mode github url", code == 0 and o == {"mode": "github", "repo": "AndreJorgeLopes/signal-copier", "number": 12})
code, o = run("mode", "AndreJorgeLopes/signal-copier#12")
check("mode github short", code == 0 and o["mode"] == "github" and o["number"] == 12)
code, o = run("mode", "MES-4414")
check("mode jira key", code == 0 and o == {"mode": "jira", "key": "MES-4414"})
code, o = run("mode", "https://aircall.atlassian.net/browse/MES-4414")
check("mode jira url", code == 0 and o["key"] == "MES-4414")
code, _ = run("mode", "https://gitlab.com/groups/aircall/-/epics/77")
check("mode gitlab abstains", code == 10)
code, _ = run("mode", "MES-1 and MES-2")
check("mode two keys abstains", code == 10)
code, _ = run("mode", "the UTF-8 epic")
check("mode free text with key-like token abstains", code == 10)
code, _ = run("mode", "gitlab.com/group/project#12")
check("mode gitlab short form abstains", code == 10)
code, _ = run("mode", "the tags epic")
check("mode free text abstains", code == 10)

# gate
with tempfile.TemporaryDirectory() as d:
    p = os.path.join(d, "CLAUDE.md")
    with open(p, "w") as f:
        f.write("# Proj\n\n## Merge gate (André approved this on 2026-10-22, for this repository only)\n\nrules\n")
    code, o = run("gate", p)
    check("gate heading found", code == 0 and o["merge_gate"] is True and o["heading"].startswith("Merge gate"))
    with open(p, "w") as f:
        f.write("# Proj\n\n## Conventions\n\n## Safety\n")
    code, o = run("gate", p)
    check("gate absent", code == 0 and o == {"merge_gate": False})
    with open(p, "w") as f:
        f.write("# Proj\n\nWe have no merge gate yet.\n")
    code, _ = run("gate", p)
    check("gate prose mention abstains", code == 10)
    with open(p, "w") as f:
        f.write("# Proj\n\n```md\n## Merge gate\n```\n\n## Conventions\n")
    code, o = run("gate", p)
    check("gate heading inside fence ignored", not (code == 0 and o.get("merge_gate") is True))
    code, o = run("gate", os.path.join(d, "missing.md"))
    check("gate missing file is no gate", code == 0 and o["merge_gate"] is False)

# premerge
code, o = run("premerge", stdin=pr([c(f"REVIEW: APPROVE at {HEAD[:7]}", "2026-10-24T10:00:00Z")]))
check("premerge ready", code == 0 and o["ready"] is True
      and o["merge_cmd"] == f"gh pr merge 51 --squash --match-head-commit {HEAD}")
code, o = run("premerge", "AndreJorgeLopes/acme", stdin=pr([c(f"REVIEW: APPROVE at {HEAD[:7]}", "2026-10-24T10:00:00Z")]))
check("premerge repo in merge_cmd", o.get("merge_cmd") == f"gh pr merge 51 --repo AndreJorgeLopes/acme --squash --match-head-commit {HEAD}")
code, o = run("premerge", stdin=pr([c(f"REVIEW: APPROVE at {OLD}", "2026-10-24T10:00:00Z")]))
check("premerge stale approval", code == 0 and o["ready"] is False and "re-check" in " ".join(o["reasons"]))
code, o = run("premerge", stdin=pr([c("Looks good, approved.", "2026-10-24T10:00:00Z")]))
check("premerge free-text approval is not a verdict", code == 0 and o["ready"] is False)
code, o = run("premerge", stdin=pr([c("REVIEW: APPROVE", "2026-10-24T10:00:00Z")]))
check("premerge approve without sha", code == 0 and o["ready"] is False)
code, o = run("premerge", stdin=pr([c(f"REVIEW: APPROVE at {HEAD[:7]}", "2026-10-24T10:00:00Z"),
                                    c(f"REVIEW: CHANGES REQUESTED at {HEAD[:7]}", "2026-10-24T11:00:00Z")]))
check("premerge latest verdict wins", code == 0 and o["ready"] is False)
code, o = run("premerge", stdin=pr([c(f"REVIEW: APPROVE at {HEAD[:7]}", "2026-10-24T10:00:00Z")],
                                   checks=[{"__typename": "CheckRun", "status": "IN_PROGRESS", "conclusion": None}]))
check("premerge pending ci", code == 0 and o["ready"] is False)
code, o = run("premerge", stdin=pr([c(f"REVIEW: APPROVE at {HEAD[:7]}", "2026-10-24T10:00:00Z")],
                                   checks=[{"__typename": "StatusContext", "state": "FAILURE"}]))
check("premerge failed status", code == 0 and o["ready"] is False)
code, _ = run("premerge", stdin=pr([c(f"REVIEW: APPROVE at {HEAD[:7]}", "2026-10-24T10:00:00Z")], checks=[]))
check("premerge no ci abstains", code == 10)
T = "2026-10-24T10:00:00Z"
code, o = run("premerge", stdin=pr([c(f"> REVIEW: APPROVE at {HEAD[:7]}\n\nREVIEW: CHANGES REQUESTED at {HEAD[:7]}", T)]))
check("premerge quoted approve does not count", code == 0 and o["ready"] is False)
code, o = run("premerge", stdin=pr([c(f"ready for review: approve when ready, head {HEAD[:7]}", T)]))
check("premerge prose is not a verdict", code == 0 and o["ready"] is False)
code, o = run("premerge", stdin=pr([c(f"REVIEW: APPROVE at {OLD}\nhead {HEAD[:7]} has an unreviewed lint commit", T)]))
check("premerge sha only from verdict line", code == 0 and o["ready"] is False)
code, o = run("premerge", stdin=pr([c(f"Reviewer report, posted by the orchestrator word for word:\nREVIEW: APPROVE at {HEAD[:7]}", T)]))
check("premerge orchestrator repost counts", code == 0 and o["ready"] is True)
code, _ = run("premerge", stdin=pr([c(f"REVIEW: APPROVE at {HEAD[:7]}\nREVIEW: CHANGES REQUESTED at {HEAD[:7]}", T)]))
check("premerge two verdict lines abstains", code == 10)
code, o = run("premerge", stdin=pr([c(f"REVIEW: APPROVE at {HEAD[:7]}", T)],
                                   checks=[{"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SKIPPED"}]))
check("premerge all skipped not ready", code == 0 and o["ready"] is False)
code, o = run("premerge", stdin=pr([c(f"REVIEW: APPROVE at {HEAD[:7]}", T)], mss="BLOCKED"))
check("premerge blocked state not ready", code == 0 and o["ready"] is False)
code, _ = run("premerge", stdin="not json")
check("premerge bad json errors", code == 1)

print("ALL PASS" if not FAILS else f"{len(FAILS)} FAILED")
sys.exit(1 if FAILS else 0)
