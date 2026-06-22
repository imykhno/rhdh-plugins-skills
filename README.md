# rhdh-plugins-cursor-config

Shared Cursor configuration for the RHDH Plugins team working in the [rhdh-plugins](https://github.com/redhat-developer/rhdh-plugins) monorepo.

Each skill is a top-level directory in this repo (for example, `validate-changes/`). Install a skill into `.cursor/skills/<name>/` in the target project so Cursor agents can discover and use it.

## Setup

Copy skill directories into a local `rhdh-plugins` clone (create `.cursor/skills/` if it does not exist):

```bash
mkdir -p /path/to/rhdh-plugins/.cursor/skills
cp -R validate-changes /path/to/rhdh-plugins/.cursor/skills/
```

Skills are picked up automatically when you ask the agent to validate changes, check before push, or prepare a branch for PR.

## Available skills

| Skill | When to use | Details |
|-------|-------------|---------|
| `validate-changes` | Validate branch changes, check before push, prepare a branch for PR | [SKILL.md](validate-changes/SKILL.md) |

## validate-changes

Run CI-equivalent checks only in workspaces touched on the current branch — not the entire monorepo.

### Workspace detection

- **Scope:** all commits since the branch was created (from `git reflog`), plus staged, unstaged, and untracked changes. Pushed and unpushed branch commits are both included. If the branch creation point is not found in reflog, only working-tree changes are used.
- **Paths:** only changes under `workspaces/<name>/` where `workspaces/<name>/package.json` exists. Root-level file changes are ignored.
- **Script:** run from the `rhdh-plugins` repo root after install:

```bash
.cursor/skills/validate-changes/scripts/detect-workspaces.sh
```

All commands run inside `workspaces/<name>/`.

| Step | Command | Condition |
|------|---------|-----------|
| 1 — Config | `yarn backstage-cli config:check --lax` | `app-config.yaml` exists |
| 2 — TypeScript | `yarn tsc:full` | always |
| 3 — Build | `yarn build:all` | always |
| 4 — API reports | `yarn build:api-reports:only --ci` | always |
| 5 — Unit tests | `yarn test:all --maxWorkers=3` | always |
| 6 — E2E | `yarn start` → Playwright → stop app | `playwright.config.ts` exists |

**Not included:** Prettier and ESLint — those run via the Husky pre-commit hook on staged files.

### Execution strategy

- **One workspace detected:** all steps run in that workspace only.
- **Multiple workspaces:** steps 1–4 run in parallel across workspaces; steps 5–6 run one workspace at a time, in alphabetical order.
- **On failure:** the agent analyzes the error, proposes a fix, and waits for your approval before editing code — no silent auto-fixes.

### Further reading

- Full agent workflow and failure recovery: [SKILL.md](validate-changes/SKILL.md)
- Edge cases (multi-locale E2E, config schema, baseline diffs): [reference.md](validate-changes/reference.md)
