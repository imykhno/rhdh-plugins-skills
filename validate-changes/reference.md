# Validate Changes — Reference

## Validation pipeline

Each step runs **per detected workspace** inside `workspaces/<name>/`. Root-level file changes are ignored by detection.

| Step | Command (per workspace) | Notes |
|------|---------------------------|-------|
| 1 | `yarn backstage-cli config:check --lax` | Only if `app-config.yaml` exists in the workspace |
| 2 | `yarn tsc:full` | Full TypeScript check |
| 3 | `yarn build:all` | Report build-generated files; do not auto-stage |
| 4 | `yarn build:api-reports:only --ci` | Report new report files; do not auto-stage |
| 5 | `yarn test:all --maxWorkers=3` | Same as CI; repo-wide unit tests with coverage |
| 6 | `yarn playwright install …` then `yarn start` → `PLAYWRIGHT_URL=… yarn playwright test` → stop app | Only if `playwright.config.ts` exists; see [E2E (step 6)](#e2e-step-6-local-startteststop) |

**Not included:** Prettier and lint. The Husky pre-commit hook (`.husky/pre-commit` → `yarn lint-staged`) runs `eslint --fix` and `prettier --write` on staged files when committing. Validation assumes committed code is already formatted and linted.

## Execution strategy

| Workspaces | Steps 1–4 | Steps 5–6 |
|---------------------|-----------|-----------|
| **One** | Run in that workspace | Run 5 → 6 sequentially in that workspace |
| **Multiple** | Run **in parallel across all workspaces**, then `wait` | Run **one workspace at a time**, in alphabetical order; within each workspace run 5 → 6 |

## Workspace detection

Run `<skill-root>/scripts/detect-workspaces.sh` from the `rhdh-plugins` repo root. `<skill-root>` is the directory containing [SKILL.md](SKILL.md) — see [Installation](SKILL.md#installation) for project vs global paths. No arguments; scope is always the current branch only.

**Scope:**

| Source | What it includes |
|--------|------------------|
| Branch creation point (reflog) | **All** commits since `branch: Created from …` (pushed + unpushed) |
| Working tree | Staged, unstaged, and untracked files |

No comparison against `main`, `origin/main`, upstream, or any other branch.

If the branch creation point is not found in reflog, only working-tree changes are used.

The script prints the scope reason, base commit, and branch commit list to stderr so you can verify exactly which commits are included.

**On `main` with uncommitted work:** branch commits may be empty; staged/unstaged/untracked files are still detected.

**File sources (union):**
- `git diff --name-only <base>...HEAD` — commits on the branch since base
- `git diff --cached --name-only` — staged
- `git diff --name-only` — unstaged
- Untracked paths from `git status --porcelain`

**Rules:**
- Path `workspaces/<name>/...` → workspace `<name>` if `workspaces/<name>/package.json` exists
- Changed files outside `workspaces/` are ignored
- Output is sorted, unique workspace names

The script prints `scope:`, `base:`, and `branch commits (N):` to stderr so the agent and user can verify which commits are in scope.

## Single-workspace expectation

When the user works on one workspace in their branch, detection returns one workspace name and **all validation steps run only there**.

## Baseline diff pattern

Use a baseline snapshot to detect build/API report artifacts (not prettier/lint — those run at commit):

1. Before step 3: `git status --porcelain` → baseline
2. After build or API reports: `git status --porcelain` → current
3. New or newly-changed entries vs baseline = tool-generated changes

## Multi-workspace branches

When changes span multiple workspaces:

- Steps 1–4: run **in parallel across workspaces**
- Steps 5–6: run **one workspace at a time**, alphabetically

## Edge cases

**No workspaces detected:** No files under `workspaces/` differ from the union of branch/staged/unstaged/untracked sources. Tell the user and stop.

**Workspace missing a script:** Stop on failure for required steps (config when applicable, tsc, build, API reports, unit tests). Skip step 6 when `playwright.config.ts` is missing.

**Workspace without app-config.yaml:** Skip step 1 (config check) for that workspace.

**Workspace without playwright.config.ts:** Skip step 6 (e2e) for that workspace.

**Branch creation point not found in reflog:** Only working-tree changes (staged/unstaged/untracked) are used for detection.

**Parallel step failure:** When running steps 1–2 in parallel, if one workspace fails, stop the validation run and report which workspace failed. Do not proceed to steps 3–6.

**Uncommitted changes not yet committed:** Prettier/lint from Husky only apply to staged files at commit time. If the user has uncommitted work, remind them to commit (or stage and commit) so Husky can format/lint it before relying on validation results.

**E2E leftover process:** If step 6 fails before the `trap` runs, manually `kill` the recorded `$APP_PID` and report any leftover `yarn start` process to the user.

**E2E multi-locale workspaces** (bulk-import, adoption-insights): Playwright projects use ports 3000–3005 (one per locale). A single `yarn start` on port 3000 covers the `en` project only. Full locale coverage requires Playwright's `webServer` (omit `PLAYWRIGHT_URL`) or multiple start cycles — not the default validation flow.

**E2E legacy + NFS:** Workspace `playwright` scripts may run `test:e2e:all` (legacy then nfs sequentially). With one NFS `yarn start`, legacy-mode tests may fail or be invalid. This is a known limitation of the single-start validation flow.

## Failure recovery loop

When a validation step fails:

1. **Stop** — do not continue to later steps.
2. **Analyze** — read error output, affected files, and similar code in the repo.
3. **Propose** — present root cause, concrete fix, files to change, and ask for approval.
4. **Apply** — only after the user agrees; keep the diff minimal.
5. **Re-run** — from the failed step for the affected workspace; continue remaining steps on success.

If the re-run still fails, propose an updated fix — never apply fixes silently or skip user approval.

### Config schema: extra type definitions

Backstage `config.d.ts` files may export **only** `export interface Config`. Top-level `export type` aliases or helper interfaces cause:

```
Invalid configuration schema in …/config.d.ts, additional symbol definitions are not allowed
```

**Fix:** inline the union or helper shapes inside `Config` (see `workspaces/scorecard/plugins/scorecard-backend-module-jira/config.d.ts`). If types are needed elsewhere, move them to a separate non-config `.ts` file.

### E2E (step 6): local start/test/stop

Run only when `workspaces/<name>/playwright.config.ts` exists. Requires `build:all` (step 3) to have passed.

1. `yarn playwright install --with-deps chromium chrome`
2. `yarn start &` — capture `APP_PID=$!`
3. Wait for readiness: `until curl -sf http://localhost:7007/.backstage/health/v1/readiness; do sleep 2; done`
4. Run tests with cleanup trap:
   ```bash
   kill -9 $(lsof -t -i :3000)
   kill -9 $(lsof -t -i :7007)
   ```
5. Verify app stopped: `kill -0 $APP_PID` should fail

**Why `PLAYWRIGHT_URL`:** Most workspace configs set `webServer: []` when `PLAYWRIGHT_URL` is set, so Playwright does not spawn its own servers. Tests target the manually started app on port 3000.

**Entry point:** Use `yarn playwright test` — not `yarn test:e2e` or `npx playwright test` directly — so the workspace `playwright` script in `package.json` is honored (may route to `test:e2e:all`, `test:e2e:ci`, etc.).

**Optional `CI=true`:** Prefix the playwright command with `CI=true` to enable retries and `forbidOnly` in configs that check `process.env.CI`. Not required for local validation.

**CI difference:** GitHub Actions runs `yarn playwright test` without a manual `yarn start`; Playwright's `webServer` in `playwright.config.ts` starts and stops servers automatically. Local validation uses the explicit start/test/stop flow above.

Workspaces with `playwright.config.ts` in this repo: adoption-insights, bulk-import, extensions, global-floating-action-button, global-header, homepage, lightspeed, quickstart, scorecard, theme, translations, x2a.
