#!/usr/bin/env python3
"""Deterministic wave scheduler + eligibility filter for orchestrate-epic.

The AI does the fuzzy work (discover the epic, read tickets, parse the
dependency edges from BOTH formal Jira issuelinks AND the free-text
"Dependencies:" section, decide which edges are HARD). It then hands this
script a clean graph and this script does the parts that must be exact:
topological wave leveling, cycle detection, and the eligibility / workable
filter. Judgment stays with the AI; arithmetic stays here.

Abstain contract (lib/determinism/CONTRACT.md):
  exit 0  -> confident result on stdout (JSON)
  exit 10 -> abstain, let the AI decide (e.g. a dependency CYCLE was found,
             which is a data problem a human/AI must untangle)
  exit 1  -> hard error (malformed input); AI falls back

Input (stdin, JSON):
{
  "me": "andre.lopes@aircall.io",          # current user (email or accountId); may be null
  "resolved_status_names": ["Done", ...],  # OPTIONAL override of the resolved-name matcher
  "done_signals": ["MES-4415"],            # OPTIONAL keys the user explicitly told us are DONE
  "tickets": [
    {
      "key": "MES-4459",
      "assignee": "andre.lopes@aircall.io" | null,
      "status": "To Do",                   # human status name
      "statusCategory": "new",             # one of: new | indeterminate | done
      "blockedBy": ["MES-4415"]            # HARD in-epic blockers only (deduped by the AI)
    }, ...
  ]
}

Output (stdout, JSON): waves, eligible, workable_now, blocked, resolved,
ineligible, external_blockers, notes.
"""
import json
import sys


# A blocker no longer blocks once its ticket is at/after code review.
# statusCategory "done" always counts; otherwise match the status NAME.
# (Mirrors best-roi-task: "done category, or a status name containing Review".)
DEFAULT_RESOLVED_NAME_SUBSTRINGS = [
    "review", "qa", "ready for prod", "ready for production",
    "released", "deployed", "merged", "done", "closed",
]


def fail(msg, code):
    print(json.dumps({"error": msg}), file=sys.stderr)
    sys.exit(code)


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except Exception as e:  # malformed -> hard error, AI falls back
        fail("invalid JSON: %s" % e, 1)

    tickets = data.get("tickets")
    if not isinstance(tickets, list) or not tickets:
        fail("no tickets provided", 1)

    me = data.get("me")
    done_signals = set(data.get("done_signals") or [])
    name_subs = [s.lower() for s in
                 (data.get("resolved_status_names") or DEFAULT_RESOLVED_NAME_SUBSTRINGS)]

    by_key = {}
    for t in tickets:
        k = t.get("key")
        if not k:
            fail("a ticket is missing 'key'", 1)
        if k in by_key:
            fail("duplicate ticket key: %s" % k, 1)
        by_key[k] = t
    keys = set(by_key)

    def is_resolved(key):
        # user's explicit "it's done" signal always wins
        if key in done_signals:
            return True
        t = by_key.get(key)
        if t is None:
            return False  # unknown/external blocker: cannot confirm -> treat as blocking
        if (t.get("statusCategory") or "").lower() == "done":
            return True
        name = (t.get("status") or "").lower()
        return any(sub in name for sub in name_subs)

    def is_mine(key):
        t = by_key[key]
        a = t.get("assignee")
        return a is not None and me is not None and a == me

    def is_unassigned(key):
        return by_key[key].get("assignee") is None

    def category(key):
        return (by_key[key].get("statusCategory") or "").lower()

    # --- eligibility -------------------------------------------------------
    # Exclude tickets assigned to someone else, and tickets already resolved
    # (done / in review+). Include:
    #   (unassigned AND To Do)  OR  (mine AND (To Do OR In Progress))
    eligible, ineligible = [], []
    for k in by_key:
        assignee = by_key[k].get("assignee")
        others = assignee is not None and (me is None or assignee != me)
        cat = category(k)
        reason = None
        if others:
            reason = "assigned to someone else"
        elif is_resolved(k):
            reason = "already resolved (done / in review+)"
        elif is_unassigned(k) and cat != "new":
            reason = "unassigned but not in To Do"
        elif cat not in ("new", "indeterminate"):
            reason = "status not To Do / In Progress"
        if reason:
            ineligible.append({"key": k, "reason": reason})
        else:
            eligible.append(k)
    eligible_set = set(eligible)

    # --- edges (only among the provided set; note external blockers) -------
    external = {}
    in_set_blockers = {}
    for k in by_key:
        bb = by_key[k].get("blockedBy") or []
        in_set_blockers[k] = [b for b in bb if b in keys]
        ext = [b for b in bb if b not in keys]
        if ext:
            external[k] = ext

    # --- wave leveling via longest-path over in-set edges ------------------
    # level(t) = 0 if no in-set blockers else 1 + max(level(b)).
    level = {}
    visiting, done_mark = set(), set()
    cycle_path = []

    def compute(k, stack):
        if k in done_mark:
            return level[k]
        if k in visiting:
            # found a cycle: capture the loop for reporting
            i = stack.index(k) if k in stack else 0
            cycle_path.extend(stack[i:] + [k])
            raise ValueError("cycle")
        visiting.add(k)
        lv = 0
        for b in in_set_blockers[k]:
            lv = max(lv, 1 + compute(b, stack + [k]))
        visiting.discard(k)
        done_mark.add(k)
        level[k] = lv
        return lv

    try:
        for k in by_key:
            compute(k, [])
    except ValueError:
        # dependency cycle -> abstain, hand back to the AI/human to untangle
        print(json.dumps({
            "abstain": True,
            "reason": "dependency cycle detected",
            "cycle": cycle_path,
        }, indent=2))
        sys.exit(10)

    max_level = max(level.values()) if level else 0
    waves = []
    for lv in range(max_level + 1):
        waves.append(sorted(k for k in by_key if level[k] == lv))

    # --- workable now ------------------------------------------------------
    # eligible AND every HARD blocker (in-set or external) is resolved.
    workable_now, blocked = [], []
    for k in eligible:
        all_bb = by_key[k].get("blockedBy") or []
        unresolved = [b for b in all_bb if not is_resolved(b)]
        if unresolved:
            blocked.append({"key": k, "blockedBy": sorted(unresolved)})
        else:
            workable_now.append(k)

    notes = []
    if external:
        notes.append("Some blockers reference tickets outside the provided set; "
                     "they are treated as blocking until marked resolved (done_signals) "
                     "or included in the ticket set.")
    if me is None:
        notes.append("No 'me' provided: 'mine' eligibility could not be evaluated; "
                     "only unassigned To Do tickets are eligible.")

    out = {
        "abstain": False,
        "me": me,
        "waves": waves,
        "levels": level,
        "eligible": sorted(eligible),
        "workable_now": sorted(workable_now),
        "blocked": sorted(blocked, key=lambda x: x["key"]),
        "ineligible": sorted(ineligible, key=lambda x: x["key"]),
        "resolved": sorted(k for k in by_key if is_resolved(k)),
        "external_blockers": external,
        "notes": notes,
    }
    print(json.dumps(out, indent=2))
    sys.exit(0)


if __name__ == "__main__":
    main()
