---
name: validate-changes
description: >-
  Validates branch changes in the rhdh-plugins monorepo.
  Detects workspaces changed on the current branch and runs config, typecheck,
  build, API reports, unit tests, and Playwright e2e checks in those workspaces
  only. Use when the user asks to validate changes, check before push, or prepare
  a branch for PR.
---

# Validate changes

Validation for the `rhdh-plugins` monorepo. Workspaces live under `workspaces/<name>/`.

**Scope:** Workspaces are determined from **all commits on the current branch** (since the branch was created), plus any staged/unstaged/untracked working-tree changes. Pushed and unpushed commits are both included. If you changed one workspace, all validation runs **only in that workspace** — never across the whole monorepo.

Run steps in order. On failure, follow [Failure recovery](#failure-recovery) — analyze, propose a fix, wait for user approval, then apply and re-run.

Copy this checklist and track progress:

```
Validation Progress:
- [ ] Detect workspaces (branch-scoped)
- [ ] Step 1 — Config (config:check --lax, if app-config.yaml exists)
- [ ] Step 2 — TypeScript (tsc:full)
- [ ] Step 3 — Build (build:all)
- [ ] Step 4 — API reports (build:api-reports:only --ci)
- [ ] Step 5 — Unit tests (test:all)
- [ ] Step 6 — E2E (yarn start → yarn playwright test → stop app, if playwright.config.ts exists)
- [ ] Summarize results
```

## Step 0 — Detect workspaces

Run from the repo root:

```bash
.cursor/skills/validate-changes/scripts/detect-workspaces.sh
```

The script prints scope metadata to stderr:

```
scope: all commits since branch was created
base: 483a960b Add Successful CRUD SnackBar
branch commits (2):
  9d7910d2 made refactor
  ce8b0bdb do something
```

Report the scope, commit list, and workspace list to the user.

**Scope:** all commits on the current branch since it was created (from `git reflog`, e.g. `branch: Created from HEAD`), plus any staged/unstaged/untracked changes. Pushed and unpushed branch commits are both included.

If the branch creation point cannot be found in reflog, only working-tree changes are used.

**File sources (union):**
- Branch commits since base (`git diff --name-only <base>...HEAD`)
- Staged changes (`git diff --cached --name-only`)
- Unstaged changes (`git diff --name-only`)
- Untracked files (`git status --porcelain`)

Output is one workspace per line (e.g. `scorecard`).

**If output is empty:** tell the user no workspace changes were detected on this branch and stop.

**Before proceeding:** report the branch base and workspace list to the user.

## Execution strategy

| Workspaces detected | Steps 1–4 | Steps 5–6 |
|---------------------|-----------|-----------|
| **One** | Run in that workspace | Run 5 → 6 sequentially in that workspace |
| **Multiple** | Run **in parallel across all workspaces**, then `wait` | Run **one workspace at a time**, in alphabetical order; within each workspace run 5 → 6 |

Config and TypeScript are read-only and safe to parallelize across independent workspaces. Build, unit tests, API reports, and e2e run sequentially per workspace to avoid thrashing the machine. Step 6 starts the app manually with `yarn start`, runs Playwright, then **must stop the app** when tests finish (success or failure).

**Step 6 skip rule:** Run step 6 only when `workspaces/<name>/playwright.config.ts` exists — same condition as [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml). Skip silently for workspaces without Playwright.

Stop immediately if **any** workspace fails; report the workspace, command, and error output, then follow [Failure recovery](#failure-recovery).

## Failure recovery

When a step fails, **do not auto-fix**. Analyze the error, propose a solution, and wait for the user to approve before changing code.

### 1. Analyze

- Capture the full command output (stderr + stdout).
- Identify the failing workspace, step, file, and line if present.
- Read the relevant source files and search the repo for similar patterns (e.g. other `config.d.ts` files, existing test helpers).
- Determine the **root cause** — not just the symptom.

### 2. Propose

Present the user with a short, structured proposal:

```
## Validation failure — proposed fix

**Step:** <step number and name>
**Workspace:** <name>
**Error:** <one-line summary>

**Root cause:** <why it failed>

**Proposed fix:**
- <concrete change 1>
- <concrete change 2>

**Files to change:** <paths>

**Risk:** <low/medium — e.g. "schema-only, no runtime behavior change">

Apply this fix and re-run validation from step <N>?
```

Keep the proposal focused and minimal — match existing repo conventions, avoid over-engineering.

### 3. Wait for approval

- **Do not edit files** until the user agrees (e.g. "yes", "apply it", "go ahead").
- If the user asks questions, clarify without applying.
- If the user declines or suggests a different approach, follow their direction.

### 4. Apply and re-run

After approval:

1. Apply the proposed fix (minimal diff).
2. Re-run validation **from the failed step** for the affected workspace(s). Earlier passing steps do not need to be repeated unless the fix could affect them.
3. Continue with remaining steps if the re-run passes.
4. If the fix does not resolve the failure, analyze again and propose an updated solution — do not loop silently.

### Common failure patterns

| Step | Typical errors | Fix direction |
|------|----------------|---------------|
| 1 — Config | `additional symbol definitions are not allowed` in `config.d.ts` | Inline types inside `export interface Config`; only `Config` may be exported. See `scorecard-backend-module-jira/config.d.ts` for union-in-interface pattern. |
| 1 — Config | Missing or invalid config keys vs `app-config.yaml` | Align `config.d.ts` schema with YAML; check `@visibility` annotations. |
| 2 — TypeScript | Type errors, missing exports | Fix types/imports in changed files; run `tsc:full` to verify. |
| 3 — Build | Compile/bundle errors | Fix source; check for missing deps or wrong paths. |
| 4 — API reports | Report drift vs committed reports | Regenerate reports (`build:api-reports:only --ci`); tell user which files changed so they can stage them. |
| 5 — Unit tests | Assertion or snapshot failures | Update test expectations or fix logic; do not weaken tests without reason. |
| 6 — E2E | Playwright timeout, selector, or server startup failures | Verify `yarn start` reached readiness; set `PLAYWRIGHT_URL=http://localhost:3000`; kill leftover `yarn start` processes; update selectors or test helpers. |

See [reference.md](reference.md) for edge cases and baseline diff patterns.

## Steps 1–6 — Commands

All commands run inside `workspaces/<name>/`.

### Step 1 — Config

Run only when `workspaces/<name>/app-config.yaml` exists (same condition as CI):

```bash
cd workspaces/<name> && yarn backstage-cli config:check --lax
```

Skip this step for workspaces without `app-config.yaml`.

### Step 2 — TypeScript

```bash
cd workspaces/<name> && yarn tsc:full
```

### Step 3 — Build

```bash
cd workspaces/<name> && yarn build:all
```

Capture `git status --porcelain` before step 3. After build, compare to baseline. Report any new build-generated files but do **not** auto-stage them.

### Step 4 — API reports

```bash
cd workspaces/<name> && yarn build:api-reports:only --ci
```

After API reports, compare `git status --porcelain` to the step baseline. Report any new report files but do **not** auto-stage them.

### Step 5 — Unit tests

Same command as CI (`.github/workflows/ci.yml`):

```bash
cd workspaces/<name> && yarn test:all --maxWorkers=3
```

### Step 6 — E2E (Playwright)

Run only when `workspaces/<name>/playwright.config.ts` exists — same condition as CI. Requires step 3 (`build:all`) to have passed.

Always run step 6 **one workspace at a time**, in alphabetical order, after steps 3–5 pass for that workspace.

**6a — Start app** (background, capture PID):

```bash
cd workspaces/<name> && yarn start &
APP_PID=$!
```

**6b — Wait for readiness** before running tests:

```bash
until curl -sf http://localhost:7007/.backstage/health/v1/readiness; do sleep 2; done
```

**6c — Run tests** (use `trap` so the app is stopped even on failure):

```bash
trap 'kill $APP_PID 2>/dev/null; wait $APP_PID 2>/dev/null' EXIT
PLAYWRIGHT_URL=http://localhost:3000 yarn playwright test
```

`PLAYWRIGHT_URL` disables Playwright's built-in `webServer` so tests use the manually started app instead of spawning duplicate servers.

Use `yarn playwright test` — not `npx playwright test` directly — so the workspace `playwright` script in `package.json` is honored (may delegate to `test:e2e:all`, `test:e2e:legacy`, or other workspace-specific entry points).

**6d — Verify app stopped** (after trap runs):

```bash
kill -0 $APP_PID 2>/dev/null && echo "App still running" && exit 1
```

Report to the user that the app was started, tests ran, and the process was stopped. If step 6 fails before the trap runs, manually `kill` the recorded `$APP_PID` and report any leftover process.

See [reference.md](reference.md) for multi-locale and legacy/NFS edge cases.

## Final summary

Report to the user:

- Branch base used for detection
- Workspaces validated
- Pass/fail for each step (1–6) per workspace; note **skipped** for step 6 when no `playwright.config.ts`; for step 6, note whether the app was stopped cleanly
- Any fixes applied during this session (with file paths)
- Build-generated or API report files that may need staging
- Whether the branch looks ready

For the full PR workflow (branch creation, changesets, push): [.cursor/commands/pr.md](../../commands/pr.md)

## Additional resources

- Edge cases and script details: [reference.md](reference.md)
