---
id: ARCH-testing-ci-pipeline
title: "CI Pipeline — GitHub Actions, ShellCheck, Plugin Validation"
priority: P1
category: architecture
status: open
depends_on:
  - ARCH-testing-foundation
estimated_effort: S
files_to_touch:
  - .github/workflows/ci.yml
  - Makefile
  - README.md
---

# CI Pipeline — GitHub Actions, ShellCheck, Plugin Validation

## Context

Phase 5 of the testing infrastructure buildout (parent: `ARCH-testing-infrastructure`). Depends on `ARCH-testing-foundation` (needs at least some tests to run in CI).

This task creates the GitHub Actions CI pipeline that runs on every push and PR. It also adds ShellCheck linting as a `make lint` target and a CI badge to the README. Once this lands, every PR created by `finish-feature` or `create-pr` skills gets automatically verified.

## Steps

1. **Create `.github/workflows/ci.yml`**
   - Trigger: `push` and `pull_request` events
   - Runner: `macos-latest` (devflow targets macOS)
   - Job `test`:
     - Checkout repo
     - Install bats-core via `brew install bats-core`
     - Run `make test-all` (or `make test-unit` if test-all doesn't exist yet)
     - Cache brew dependencies for faster runs
   - Job `shellcheck`:
     - Can run on `ubuntu-latest` (ShellCheck is cross-platform)
     - Run `make lint`
   - Job `plugin-validate`:
     - Install `@anthropic-ai/claude-code` globally
     - Run `claude plugin validate devflow-plugin`
   - Set concurrency group to cancel redundant runs on same branch

2. **Add `make lint` target to Makefile**
   - Run `shellcheck lib/*.sh bin/devflow`
   - Use `--shell=bash` flag
   - Use `--severity=warning` (or `error`) as the minimum level
   - Consider `--format=gcc` for CI-friendly output
   - Optionally add `--external-sources` if lib files source each other

3. **Add CI status badge to README.md**
   - Badge format: `![CI](https://github.com/<owner>/<repo>/actions/workflows/ci.yml/badge.svg)`
   - Place at the top of README, after the title
   - Add test status and ShellCheck status as separate badges if desired

4. **Verify CI pipeline locally (optional)**
   - If `act` is installed: `act -n` for dry-run
   - Otherwise, push to a branch and verify CI runs

## Key Test Scenarios

| Scenario | Expected |
|----------|----------|
| Push to any branch | CI triggers, runs tests |
| PR opened | CI triggers, shows check status |
| All tests pass | Green check on PR |
| ShellCheck finds issues | `lint` job fails, blocks PR |
| Plugin validation fails | `plugin-validate` job fails |
| Concurrent pushes to same branch | Earlier run cancelled |

## CI Pipeline Structure

```yaml
name: CI
on:
  push:
    branches: [main, 'feature/**']
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install bats-core
        run: brew install bats-core
      - name: Run tests
        run: make test-all

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install ShellCheck
        run: sudo apt-get install -y shellcheck
      - name: Run ShellCheck
        run: make lint

  plugin-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Install Claude Code CLI
        run: npm install -g @anthropic-ai/claude-code
      - name: Validate plugin
        run: claude plugin validate devflow-plugin
```

## Acceptance Criteria

- [ ] `.github/workflows/ci.yml` exists and is valid YAML
- [ ] CI triggers on push and pull_request events
- [ ] `test` job runs `make test-all` on macos-latest
- [ ] `lint` job runs `make lint` (ShellCheck)
- [ ] `plugin-validate` job runs `claude plugin validate`
- [ ] `make lint` target exists and runs ShellCheck on `lib/*.sh` and `bin/devflow`
- [ ] `make lint` passes with zero errors at the configured severity level
- [ ] CI status badge is added to README.md
- [ ] Concurrent runs on the same branch are cancelled

## Verification

```bash
# Lint passes locally
make lint

# CI config is valid YAML
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"

# Dry-run CI locally (if act is installed)
act -n

# Push to a branch and verify CI runs
git push origin feature/testing-ci
# → Check GitHub Actions tab for green status
```

## Workflow Integration

CI becomes the automated gatekeeper for the devflow project. The workflow connects to skills as follows:

- **`finish-feature`** creates a PR → CI runs automatically → PR shows check status
- **`create-pr`** creates a PR → same CI pipeline verifies it
- **`pre-push-check`** runs `make test` locally → CI duplicates this check server-side as a safety net
- **`devflow check`** (AI review) catches logic/design issues → ShellCheck catches Bash syntax/pitfalls → together they provide comprehensive code review

The ShellCheck step is particularly valuable because it catches classes of bugs that `devflow check` (AI-based review) might miss: unquoted variables, unused variables, POSIX compliance issues, and common Bash pitfalls. This is the bridge between "agent creates PR" and "code is verified safe to merge."
