---
name: rhdh-plugins-unit-tests
description: >-
  Guides creating, updating, and reviewing Jest unit tests for Backstage
  frontend and backend plugins in the rhdh-plugins monorepo. Standards-first:
  assert behavior over implementation; mock at boundaries only; use
  mockServices, TestDatabases, and Testing Library. Use when the user asks to
  add, write, create, update, refactor, review, or improve unit tests for
  plugins, services, routers, hooks, components, or providers. Do not use for
  Playwright e2e.
---

# RHDH plugins unit tests

Unit-test guidance for Backstage plugins under `workspaces/<name>/` in
[rhdh-plugins](https://github.com/redhat-developer/rhdh-plugins).

**Standards first.** Existing tests in a package are not automatically
correct — follow this skill. Adopt local patterns only when they match
[Great ideas](#great-ideas-adopt-selectively).

## When this skill applies

Use for: add / write / create / update / refactor / review / improve
**unit tests**, including tests written as part of a feature or bugfix.

Do **not** use for Playwright e2e.

## Workflow

Copy and track:

```
Unit test progress:
- [ ] Identify unit + layer
- [ ] Read siblings for style; discard weak patterns
- [ ] Choose create vs update path
- [ ] Apply fake / mock / factory policy
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
| Hook | reusable `useX` data/state hooks |
| Component | presentational React |
| Extension | NFS blueprints / extensions |

Details: [reference.md](reference.md).

### 2. Create vs update

**Create**

- Prefer colocated `Foo.test.ts` / `Foo.test.tsx`.
- If the package already dominates with `__tests__/`, follow that package.
- Read sibling tests for Apache headers and `describe('UnitName')` style.
  Discard spies, private-method tests, and mock theater — do not copy them.

**Update / refactor**

- Keep behavioral coverage; do not weaken product contracts.
- When touching a spy-heavy file, rewrite the cases you touch; do not add
  a new spy next to old ones.
- Remove internal spies on pure helpers; assert outputs instead.
- Extract duplicated blobs into fixture builders.
- Do not test private methods (`as any` / `(x as any).privateFn`).

### 3. Fake vs mock vs factory

| Kind | Use for | Examples |
|------|---------|----------|
| Keep real | Pure helpers, mappers, validators, same-layer utils | parsers, type guards |
| Fake | Simplified real behavior | `mockServices.rootConfig({ data })`, `mockApis.config`, `TestDatabases` |
| Jest mock | Assert a port call | `toHaveBeenCalledWith` on loader, DB, catalog, fetch |
| Factory | Install fake/mock into a harness | `mockServices.*.factory()` in `startTestBackend` / `renderInTestApp` |

Mock **ports and externals**, not every import.

**Config:** do not import `ConfigReader` from `@backstage/config`. Use
`mockServices.rootConfig({ data })` from `@backstage/backend-test-utils`.

### 4. Assert policy

Prefer:

1. Return value / thrown error / HTTP status+body / visible UI state
2. `toHaveBeenCalledWith` **only** for ports (loader, DB, catalog, fetch)

Avoid as primary proof: spies on local pure helpers/mappers.

### 5. Frontend and hooks

- Queries: `getByRole` first, then label/text; `getByTestId` last.
- Interactions: `@testing-library/user-event`. Async UI: `findBy*`, not
  `waitFor` + `getBy*`.
- i18n: do not lock English copy when keys are the contract; use
  `mockApis.translation()` / default messages.
- Prefer testing the component that uses a hook. `renderHook` only for
  reusable hooks. Mock the plugin API / fetch seam — never `useQuery` or
  the whole `@backstage/core-plugin-api` module.
- One-off hooks used by a single component: no dedicated hook test.
- Allowed snapshot: `ExtensionTester.snapshot()` for extension tree
  contracts only. Do not snapshot DOM.

### 6. Case order (prefer)

Prefer this order; do not rewrite a valid suite only to match it:

1. Invalid input / error path
2. Defaults / empty
3. Happy path (assert output)
4. Meaningful edges
5. Port interaction (if the unit’s job is orchestration)

### 7. Run tests

1. Identify `workspaces/<name>/` from the file path; read that workspace’s
   `AGENTS.md` if present.
2. Install and build from the workspace root. Run tests **filtered**.
3. Never run unfiltered monorepo-wide tests.

Default (package, matches Backstage CLI):

```bash
cd workspaces/<name>/plugins/<package>
yarn test <UnitOrFileName>
```

Fallback (workspace root). `CI=true` enables long-running Backstage DB tests:

```bash
cd workspaces/<name>
CI=true yarn test --watchAll=false -- --testPathPattern=<UnitOrFileName>
```

## Core rules

1. **Behavior over implementation** — input → observable output.
2. **Black box** — do not dictate private structure.
3. **Scalability** — harmless internal refactors should not force mass test edits.
4. **One behavior per `it`** — name `should <outcome> when <condition>`.
5. **Determinism** — fixed timestamps and `Date.now` / clocks; no
   `Math.random`; no real network; no real Docker unless `TestDatabases`
   is the subject.
6. **No false confidence** — skip export-only smoke tests as sole coverage.
7. **Contracts** — lock stable public IDs, config paths, and HTTP shapes when
   they are product API.
8. **Success criterion** — a private-helper rename must not force test edits;
   a real behavior change must fail tests.

Official principles:
[Testing Backend Plugins and Modules](https://backstage.io/docs/backend-system/building-plugins-and-modules/testing/).
[Testing Frontend Plugins](https://backstage.io/docs/frontend-system/building-plugins/testing/).
[Testing with Jest (Legacy)](https://backstage.io/docs/plugins/testing/).

## Great ideas (adopt selectively)

Patterns worth reusing when present in a package:

- Constructor dependency injection
- Fixture builders with overrides (`__fixtures__/mock*.ts`, entity builders)
- `mockServices.rootConfig({ data })` for config
- `TestDatabases` when SQL/repository correctness is the subject
- Extracted pure builders/validators for cheap unit tests
- Frontend: separate presentation vs data-fetching; Testing Library;
  `@backstage/frontend-test-utils` for NFS extensions

Reuse **builders** (for example under `plugins/*/__fixtures__/`), not
spy-heavy suites.

## Anti-patterns (do not copy)

- Spying pure local helpers/mappers as the main assertion
- Testing private APIs
- Mock theater (mocking every import)
- Mocking `useQuery` or `@backstage/core-plugin-api` as a module
- `as any` on ports when a typed fake exists
- DOM snapshots (extension-tree `snapshot()` is the exception)
- `ConfigReader` from `@backstage/config` — use `mockServices.rootConfig`
- Brittle UI asserts on CSS, theme tokens, or exact locale copy when i18n
  keys are the contract
- Replacing repository `TestDatabases` tests with Knex mocks and calling
  that “SQL coverage”

## Definition of done

- [ ] One unit, correct layer
- [ ] Externals faked/mocked; pure logic real
- [ ] Outputs/errors asserted before (optional) port calls
- [ ] Fixtures via builders when data is non-trivial
- [ ] Product contracts locked where relevant
- [ ] No private-method tests; a private rename would not require test edits
- [ ] UI uses `getByRole` / `userEvent` where applicable
- [ ] Filtered Jest run passes for the changed tests

## Additional resources

- Layer tooling, create/update procedures: [reference.md](reference.md)
- Short good templates: [examples.md](examples.md)
- [Testing with Jest (Legacy)](https://backstage.io/docs/plugins/testing/)
- [Testing Frontend Plugins](https://backstage.io/docs/frontend-system/building-plugins/testing/)
- [Testing Backend Plugins](https://backstage.io/docs/backend-system/building-plugins-and-modules/testing/)
- [Testing with Utility APIs](https://backstage.io/docs/frontend-system/utility-apis/testing/)
- [Testing Library principles](https://testing-library.com/docs/guiding-principles/)
- [Query priority](https://testing-library.com/docs/queries/about/)
- [mockServices API](https://backstage.io/api/stable/modules/_backstage_backend-test-utils.index.mockServices.html)
