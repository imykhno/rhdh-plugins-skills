---
name: backstage-unit-tests
description: >-
  Guides creating and updating Jest unit tests for Backstage frontend and
  backend plugins in the rhdh-plugins monorepo. Standards-first: assert
  behavior over implementation, mock at boundaries only. Use when the user
  asks to add, write, create, update, refactor, or improve unit tests for
  plugins, services, routers, hooks, components, or providers.
---

# Backstage unit tests

Unit-test guidance for Backstage plugins under `workspaces/<name>/` in
[rhdh-plugins](https://github.com/redhat-developer/rhdh-plugins).

**Standards first.** Existing tests in a package are not automatically
correct — follow this skill. Adopt local patterns only when they match
[Great ideas](#great-ideas-adopt-selectively).

## Installation

Cursor loads this skill from **either** location:

| Scope | Path |
|-------|------|
| Project | `.cursor/skills/backstage-unit-tests/` in the `rhdh-plugins` clone |
| Global | `~/.cursor/skills/backstage-unit-tests/` or `~/.cursor/skills/rhdh-plugins-skills/backstage-unit-tests/` |

Source repo: [rhdh-plugins-skills](https://github.com/imykhno/rhdh-plugins-skills).
When loaded, `<skill-root>` is the directory that contains this `SKILL.md`.

## When this skill applies

Use for: add / write / create / update / refactor / improve **unit tests**.

Do **not** use for Playwright e2e or full workspace validation (use
`validate-changes`).

## Workflow

Copy and track:

```
Unit test progress:
- [ ] Identify unit + layer
- [ ] Choose create vs update path
- [ ] Apply mock / assert policy
- [ ] Write or refactor cases
- [ ] Run filtered package tests
- [ ] Definition of done
```

### 1. Identify the unit and layer

Read the source under test. Classify:

| Layer | Examples |
|-------|----------|
| Pure util / mapper / validator | parsers, builders, schema helpers |
| Service / strategy | DI classes that orchestrate ports |
| Router / action | Express routes, scaffolder actions |
| Repository | Knex / SQL access |
| Provider / HTTP client | metric providers, external APIs |
| Frontend API client | discovery + fetch wrappers |
| Hook | `useX` data/state hooks |
| Component | presentational React |
| Extension | NFS blueprints / extensions |

Details: [reference.md](reference.md).

### 2. Create vs update

**Create**

- Prefer colocated `Foo.test.ts` / `Foo.test.tsx`.
- If the package already dominates with `__tests__/`, follow that package.
- Match Apache headers and `describe('UnitName')` style of sibling files.

**Update / refactor**

- Keep behavioral coverage; do not weaken product contracts.
- Remove internal spies on pure helpers; assert outputs instead.
- Extract duplicated blobs into fixture builders.
- Do not test private methods (`as any` / `(x as any).privateFn`).

### 3. Mock policy

| Keep real | Mock or fake |
|-----------|----------------|
| Pure helpers, mappers, validators, type guards | Catalog, auth, DB ports, HTTP clients, fetch |
| Small same-layer utils | `mockServices.*`, plugin client classes |
| | react-query / `useApi` when testing hooks/UI in isolation |

Mock **ports and externals**, not every import.

**Config in unit tests:** do not use
`import { ConfigReader } from '@backstage/config';`.
If config needs to be created, use
`import { mockServices } from '@backstage/backend-test-utils';`
and `mockServices.rootConfig({ data })`.

### 4. Assert policy

Prefer:

1. Return value / thrown error / HTTP status+body / visible UI state
2. `toHaveBeenCalledWith` **only** for ports (loader, DB, catalog, fetch)

Avoid as primary proof: spies on local pure helpers/mappers.

### 5. Case order

1. Invalid input / error path  
2. Defaults / empty  
3. Happy path (assert output)  
4. Meaningful edges  
5. Port interaction (if the unit’s job is orchestration)

### 6. Run tests

1. Identify `workspaces/<name>/` from the file path; read that workspace’s
   `AGENTS.md` if present.
2. Use the `rhdh-workspace` skill norms for yarn: install/build from
   workspace root; run tests **filtered** (package dir or
   `--testPathPattern`).
3. Never run unfiltered monorepo-wide tests.

Typical:

```bash
cd workspaces/<name>
CI=true yarn test --watchAll=false -- --testPathPattern=<UnitOrFileName>
```

Or from the package: `yarn test` / `backstage-cli package test` with a path
filter.

## Core rules

1. **Behavior over implementation** — input → observable output.
2. **Black box** — do not dictate private structure.
3. **Scalability** — harmless internal refactors should not force mass test edits.
4. **One behavior per `it`** — name `should <outcome> when <condition>`.
5. **Determinism** — fixed timestamps; no real network in unit tests.
6. **No false confidence** — skip export-only smoke tests as sole coverage.
7. **Contracts** — lock stable public IDs, config paths, and HTTP shapes when
   they are product API.

Official principles:
[Testing with Jest](https://backstage.io/docs/plugins/testing/).

## Great ideas (adopt selectively)

Patterns worth reusing when present in a package:

- Constructor dependency injection
- Fixture builders with overrides (`__fixtures__/mock*.ts`, entity builders)
- `mockServices.rootConfig({ data })` for config (not `ConfigReader`)
- `TestDatabases` when SQL/repository correctness is the subject
- Extracted pure builders/validators for cheap unit tests
- Frontend: separate presentation vs data-fetching; Testing Library;
  `@backstage/frontend-test-utils` for NFS extensions

Scorecard example (style only): builders under
`plugins/*/__fixtures__/` — reuse the **builder** idea, not spy-heavy suites.

## Anti-patterns (do not copy)

- Spying pure local helpers/mappers as the main assertion
- Testing private APIs
- Mock theater (mocking every import)
- `ConfigReader` from `@backstage/config` — use `mockServices.rootConfig` instead
- Brittle UI asserts on CSS, theme tokens, or exact locale copy when i18n
  keys are the contract
- Replacing repository `TestDatabases` tests with Knex mocks and calling
  that “SQL coverage”

## Definition of done

- [ ] One unit, correct layer
- [ ] Externals mocked; pure logic real
- [ ] Outputs/errors asserted before (optional) port calls
- [ ] Fixtures via builders when data is non-trivial
- [ ] Product contracts locked where relevant
- [ ] No private-method tests
- [ ] Filtered Jest run passes for the changed tests

## Additional resources

- Layer tooling, create/update procedures: [reference.md](reference.md)
- Short good templates: [examples.md](examples.md)
- Frontend: [Testing Frontend Plugins](https://backstage.io/docs/frontend-system/building-plugins/testing/)
- Backend: [Testing Backend Plugins](https://backstage.io/docs/backend-system/building-plugins-and-modules/testing/)
