#!/usr/bin/env python3
"""gate.py: the deterministic checks of orchestrate-epic's GitHub and merge-gate modes.

Pure stdlib. Obeys the determinism contract (~/.claude/lib/determinism/CONTRACT.md):
exit 0 = confident JSON on stdout, 10 = abstain (the AI decides), 1 = error.
Sound, not complete: every case this script is not sure about abstains.

Subcommands:
  gate.py mode <epic-ref>          Which mode the epic reference selects.
      {"mode":"github","repo":"owner/repo","number":12}   for a GitHub issue URL or owner/repo#12
      {"mode":"jira","key":"MES-4414"}                    for a Jira key or a Jira browse URL
      exit 10 for anything else (GitLab epic URL, two candidates, free text).

  gate.py gate <path/to/CLAUDE.md> Does the target repo define a merge gate?
      {"merge_gate":true,"heading":"..."}   a Markdown heading that starts with "Merge gate"
      {"merge_gate":false}                  no such heading and no mention of "merge gate"
      exit 10 when "merge gate" is mentioned but is not a heading (the AI reads it).
      A missing file gives {"merge_gate":false} (no CLAUDE.md, no gate: the safe answer).

  gate.py premerge [owner/repo] < pr.json   Is the PR ready for the gated merge?
      stdin = `gh pr view <n> --json number,state,headRefOid,comments,statusCheckRollup`
      {"ready":bool,"head":"<sha>","reasons":[...],"merge_cmd":"gh pr merge ..."}
      exit 10 when the PR has no CI checks at all (the AI asks: no CI, or not reported yet?).
"""
import json
import os
import re
import sys

ABSTAIN = 10

GH_URL = re.compile(r"github\.com/([\w.-]+/[\w.-]+)/issues/(\d+)")
GH_SHORT = re.compile(r"(?<![\w/.-])([\w.-]+/[\w.-]+)#(\d+)\b")
JIRA_KEY = re.compile(r"\b([A-Z][A-Z0-9]+-\d+)\b")
GATE_HEADING = re.compile(r"^\s{0,3}#{1,6}\s+(merge gate\b.*)$", re.IGNORECASE)
VERDICT = re.compile(r"REVIEW:\s*(APPROVE|CHANGES REQUESTED)\b", re.IGNORECASE)
SHA = re.compile(r"\b[0-9a-f]{7,40}\b")
CHECK_OK = {"SUCCESS", "NEUTRAL", "SKIPPED"}


def out(obj, code=0):
    print(json.dumps(obj))
    sys.exit(code)


def cmd_mode(ref):
    gh = {(m.group(1), int(m.group(2))) for m in GH_URL.finditer(ref)}
    if not gh:
        gh = {(m.group(1), int(m.group(2))) for m in GH_SHORT.finditer(ref)}
    jira = set() if "github.com" in ref else set(JIRA_KEY.findall(ref))
    if len(gh) == 1 and not jira:
        repo, num = gh.pop()
        out({"mode": "github", "repo": repo, "number": num})
    if len(jira) == 1 and not gh and "gitlab" not in ref.lower():
        out({"mode": "jira", "key": jira.pop()})
    out({"abstain": True, "reason": "no single unambiguous epic reference"}, ABSTAIN)


def cmd_gate(path):
    if not os.path.isfile(path):
        out({"merge_gate": False, "reason": "no CLAUDE.md"})
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    headings = [m.group(1).strip() for m in map(GATE_HEADING.match, lines) if m]
    if len(headings) == 1:
        out({"merge_gate": True, "heading": headings[0]})
    if len(headings) > 1:
        out({"abstain": True, "reason": "several merge-gate headings", "headings": headings}, ABSTAIN)
    if any("merge gate" in l.lower() for l in lines):
        out({"abstain": True, "reason": "merge gate mentioned, but not as a heading"}, ABSTAIN)
    out({"merge_gate": False})


def _check_state(c):
    # CheckRun has status/conclusion; StatusContext has state.
    if c.get("__typename") == "StatusContext" or ("state" in c and "conclusion" not in c):
        s = (c.get("state") or "").upper()
        return "ok" if s == "SUCCESS" else ("pending" if s in ("PENDING", "EXPECTED", "") else "fail")
    if (c.get("status") or "").upper() != "COMPLETED":
        return "pending"
    return "ok" if (c.get("conclusion") or "").upper() in CHECK_OK else "fail"


def cmd_premerge(raw, repo=None):
    try:
        pr = json.loads(raw)
        head = pr["headRefOid"]
        number = pr["number"]
    except (ValueError, KeyError, TypeError) as e:
        out({"error": f"bad gh pr view JSON: {e}"}, 1)
    reasons = []
    if (pr.get("state") or "").upper() != "OPEN":
        reasons.append(f"PR is {pr.get('state')}, not OPEN")

    checks = pr.get("statusCheckRollup") or []
    if not checks:
        out({"abstain": True, "reason": "no CI checks on the PR", "head": head}, ABSTAIN)
    states = [_check_state(c) for c in checks]
    if "fail" in states:
        reasons.append("a CI check failed")
    elif "pending" in states:
        reasons.append("CI checks are still running")

    verdicts = []
    for c in pr.get("comments") or []:
        m = VERDICT.search(c.get("body") or "")
        if m:
            verdicts.append((c.get("createdAt") or "", m.group(1).upper(), c.get("body") or ""))
    if not verdicts:
        reasons.append("no REVIEW: verdict comment")
    else:
        _, verdict, body = sorted(verdicts)[-1]
        shas = SHA.findall(body.lower())
        if verdict != "APPROVE":
            reasons.append("latest verdict is CHANGES REQUESTED")
        elif not shas:
            reasons.append("the APPROVE verdict names no head SHA")
        elif not any(head.lower().startswith(s) for s in shas):
            reasons.append(f"the APPROVE verdict is for {shas[0]}, not the current head {head[:7]}: re-check needed")

    out({
        "ready": not reasons,
        "head": head,
        "reasons": reasons,
        "merge_cmd": f"gh pr merge {number}" + (f" --repo {repo}" if repo else "") + f" --squash --match-head-commit {head}",
    })


def main(argv):
    if len(argv) < 2:
        out({"error": "usage: gate.py mode <ref> | gate <CLAUDE.md> | premerge [owner/repo] < pr.json"}, 1)
    sub = argv[1]
    if sub == "mode" and len(argv) == 3:
        cmd_mode(argv[2])
    if sub == "gate" and len(argv) == 3:
        cmd_gate(argv[2])
    if sub == "premerge" and len(argv) <= 3:
        cmd_premerge(sys.stdin.read(), argv[2] if len(argv) == 3 else None)
    out({"error": f"unknown or malformed subcommand: {argv[1:]}"}, 1)


if __name__ == "__main__":
    main(sys.argv)
