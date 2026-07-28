#!/usr/bin/env python3
"""devflow branch-guard — Claude Code PreToolUse(Bash) hook logic.

Blocks a `git checkout` / `git switch` that would move a repo's PRIMARY clone
onto a non-base (feature) branch, in repos that use the worktree flow. Feature
work belongs in an isolated worktree, so the primary clone — and anything
symlinked to it (e.g. a devflow plugin install) — never silently serves
in-progress branch code.

ALWAYS allowed (fail-open — never block by guessing):
  - base branches (main/develop/staging/…, configurable)
  - ANY checkout inside a linked worktree
  - path restores (`git checkout -- <file>`, `git checkout .`, `-p`)
  - `git checkout -` / `git switch -` (previous branch — cannot classify)
  - repos NOT using the worktree flow (no .worktrunk.toml, no linked worktrees,
    not under a configured enforce-root)
  - anything that can't be parsed / classified confidently

PreToolUse protocol: exit 0 = allow; exit 2 + stderr = BLOCK (stderr shown to
the agent). Reads the hook JSON payload on stdin.

Config is OPTIONAL and PERSONAL (never shipped in the repo):
  ~/.config/devflow/branch-guard.json
    { "off": false, "base_branches": ["release/*"], "enforce_roots": ["~/dev"] }
  Env overrides: DEVFLOW_BRANCH_GUARD_OFF=1,
    DEVFLOW_BRANCH_GUARD_BASE_BRANCHES=a,b, DEVFLOW_BRANCH_GUARD_ROOTS=/p1:/p2
"""
import sys
import os
import json
import shlex
import subprocess

BASE_DEFAULT = {
    "main", "master", "develop", "dev", "development",
    "stage", "staging", "sandbox", "release", "trunk",
    "prod", "production", "next", "canary", "hotfix",
}
OPS = {"&&", "||", ";", "|", "&", "\n"}


def allow():
    sys.exit(0)


def block(msg):
    sys.stderr.write(msg)
    sys.exit(2)


def load_config():
    base = set(BASE_DEFAULT)
    roots = []
    path = os.path.expanduser("~/.config/devflow/branch-guard.json")
    try:
        with open(path) as f:
            cfg = json.load(f)
        if cfg.get("off"):
            allow()
        base |= {str(b) for b in cfg.get("base_branches", [])}
        roots += [os.path.abspath(os.path.expanduser(r))
                  for r in cfg.get("enforce_roots", [])]
    except FileNotFoundError:
        pass
    except Exception:
        pass  # malformed config must never block work
    if os.environ.get("DEVFLOW_BRANCH_GUARD_OFF") == "1":
        allow()
    env_base = os.environ.get("DEVFLOW_BRANCH_GUARD_BASE_BRANCHES")
    if env_base:
        base |= {b.strip() for b in env_base.split(",") if b.strip()}
    env_roots = os.environ.get("DEVFLOW_BRANCH_GUARD_ROOTS")
    if env_roots:
        roots += [os.path.abspath(os.path.expanduser(r))
                  for r in env_roots.split(":") if r]
    return base, roots


def git(dirpath, *args):
    try:
        r = subprocess.run(["git", "-C", dirpath, *args],
                           capture_output=True, text=True, timeout=5)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except Exception:
        return 1, "", ""


def resolve_dir(base_cwd, gitargs):
    """Honor `git -C <dir>` (relative dirs resolved against the session cwd)."""
    d = base_cwd
    i = 0
    while i < len(gitargs):
        if gitargs[i] == "-C" and i + 1 < len(gitargs):
            nd = gitargs[i + 1]
            d = nd if os.path.isabs(nd) else os.path.join(d, nd)
            i += 2
            continue
        i += 1
    return d


def find_subcommand(gitargs):
    """First non-option token = the git subcommand. Skip global opts + their values."""
    skip_val = {"-C", "-c", "--namespace", "--git-dir", "--work-tree", "--exec-path"}
    i = 0
    while i < len(gitargs):
        a = gitargs[i]
        if a in skip_val:
            i += 2
            continue
        if a.startswith("-"):
            i += 1
            continue
        return a, gitargs[i + 1:]
    return None, []


def parse_target(sub, rest):
    """Return (branch, is_create) for a branch MOVE, else (None, False).

    Returns None for path restores, `-`, patch mode, or when no branch operand
    is present — i.e. anything that is not a clear move onto a named branch.
    """
    create_takes_value = {"-b", "-B", "-c", "-C", "--orphan"}
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--":
            return None, False          # path restore
        if a in ("-", "."):
            return None, False          # previous-branch / path
        if a in ("-p", "--patch"):
            return None, False          # interactive patch, not a switch
        if a in create_takes_value:
            return (rest[i + 1], True) if i + 1 < len(rest) else (None, False)
        if a.startswith("-"):
            # skip flags that consume a value so we don't mistake it for the branch
            if a in ("--start-point", "-t", "--track"):
                i += 2
                continue
            i += 1
            continue
        return a, False                 # first positional operand = branch/sha/path
    return None, False


def build_message(branch, top):
    repo = os.path.basename(top.rstrip("/")) or "repo"
    slug = branch.replace("/", "-")
    return (
        "\U0001F6AB devflow branch-guard blocked this command.\n\n"
        f"Refusing to move the PRIMARY clone of '{repo}' onto feature branch "
        f"'{branch}'.\n"
        "This repo uses the worktree flow, so the primary clone must stay on a "
        "base branch (main / develop / staging / ...). Feature work goes in an "
        "isolated worktree, so the clone (and anything symlinked to it, e.g. a "
        "devflow plugin install) never silently serves in-progress branch code.\n\n"
        "Do this instead:\n"
        f"  devflow worktree {branch}\n"
        f"      -> creates ~/dev/.worktrees/{repo}/{slug} and moves you there\n"
        "  # fallback if worktrunk misplaces the path:\n"
        f"  git worktree add ~/dev/.worktrees/{repo}/{slug} -b {branch}\n\n"
        "Then do the work inside that worktree. Base branches are always allowed.\n"
        "Escape hatches: export DEVFLOW_BRANCH_GUARD_OFF=1, or set \"off\": true / add "
        "the branch to \"base_branches\" in ~/.config/devflow/branch-guard.json."
    )


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        allow()

    cmd = ((payload.get("tool_input") or {}).get("command") or "")
    cwd = payload.get("cwd") or os.getcwd()

    # Fast pre-filter: skip the vast majority of commands with no git work.
    if "git" not in cmd or ("checkout" not in cmd and "switch" not in cmd):
        allow()

    base, roots = load_config()
    base_lower = {b.lower() for b in base}

    try:
        toks = shlex.split(cmd, posix=True)
    except Exception:
        allow()  # unparseable command -> never block

    n = len(toks)
    i = 0
    cmd_head = True  # True at the start of a simple command (after a shell operator)
    while i < n:
        t = toks[i]
        if t in OPS:
            cmd_head = True
            i += 1
            continue
        if cmd_head and t == "git":
            j = i + 1
            seg = []
            while j < n and toks[j] not in OPS:
                seg.append(toks[j])
                j += 1
            d = resolve_dir(cwd, seg)
            sub, rest = find_subcommand(seg)
            if sub in ("checkout", "switch"):
                branch, is_create = parse_target(sub, rest)
                if branch and branch.lower() not in base_lower:
                    _guard_one(d, branch, is_create, roots)
            i = j
            continue
        cmd_head = False
        i += 1
    allow()


def _guard_one(d, branch, is_create, roots):
    rc, top, _ = git(d, "rev-parse", "--show-toplevel")
    if rc != 0 or not top:
        return  # not a git repo we can resolve -> allow
    _, gitdir, _ = git(d, "rev-parse", "--absolute-git-dir")
    if "/worktrees/" in gitdir:
        return  # inside a linked worktree -> feature branches are fine here

    # Is this a worktree-flow repo?
    flow = os.path.exists(os.path.join(top, ".worktrunk.toml"))
    if not flow:
        _, wl, _ = git(d, "worktree", "list", "--porcelain")
        flow = wl.count("worktree ") > 1  # has >=1 linked worktree
    if not flow and roots:
        ap = os.path.abspath(top)
        flow = any(ap == r or ap.startswith(r + os.sep) for r in roots)
    if not flow:
        return  # normal repo, not the worktree flow -> allow

    # Confirm it is really a branch move: a create, or an existing local branch.
    guard = is_create
    if not guard:
        rc2, _, _ = git(d, "show-ref", "--verify", "--quiet", "refs/heads/" + branch)
        guard = (rc2 == 0)
    if guard:
        block(build_message(branch, top))


if __name__ == "__main__":
    main()
