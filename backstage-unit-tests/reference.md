# Backstage unit tests — reference

Companion to [SKILL.md](SKILL.md). Read when choosing tooling or running a
create/update procedure.

## Layer → tooling

| Layer | Primary tools | Mock / fake |
|-------|---------------|-------------|
| Pure util / mapper / validator | Jest `expect` | Usually nothing; use `mockServices.rootConfig` if reading `Config` (never `ConfigReader`) |
| Service / strategy | Jest + constructor DI | Next-layer ports (`jest.fn`, `mockServices`, fixture DB ports) |
| Router / action | `supertest` + Express app from `createRouter` / action factory | Services behind the route; `mockServices` for auth/permissions/config |
| Full backend harness | `startTestBackend` from `@backstage/backend-test-utils` | `mockServices` factories; features under test |
| Repository / SQL | `TestDatabases` + migrations from `@backstage/backend-test-utils` | Do not mock Knex for correctness claims |
| Outbound HTTP client | `msw` + `registerMswTestHooks` | Handler rules; reject unmatched traffic |
| Provider wrapping a client | Jest | Mock the client class; keep provider logic real |
| Frontend API client | Jest | Mock `discoveryApi` / `fetchApi` |
| Hook | `renderHook` from Testing Library | `useApi`, react-query / fetch seam |
| Presentational component | `render` + `@testing-library/react` | Data hooks, charts, heavy Backstage chrome |
| Legacy test app wrap | `renderInTestApp` / `TestApiProvider` from `@backstage/test-utils` | `apis` / mock utility APIs |
| NFS extension | `createExtensionTester`, `renderInTestApp`, `mockApis` from `@backstage/frontend-test-utils` | Extension inputs, utility APIs, `mountedRoutes` |

### Packages (typical)

- Backend: `@backstage/backend-test-utils`
- Frontend (legacy helpers still common): `@backstage/test-utils`
- Frontend (NFS): `@backstage/frontend-test-utils`
- React: `@testing-library/react`, `@testing-library/user-event`, `@testing-library/jest-dom`
- HTTP route asserts: `supertest`
- HTTP stubbing: `msw`

Official docs:

- [Testing with Jest](https://backstage.io/docs/plugins/testing/)
- [Testing Frontend Plugins](https://backstage.io/docs/frontend-system/building-plugins/testing/)
- [Testing Backend Plugins and Modules](https://backstage.io/docs/backend-system/building-plugins-and-modules/testing/)
- [Testing with Utility APIs](https://backstage.io/docs/frontend-system/utility-apis/testing/)

## Decision tree

```text
Pure transform / parse / validate?
  → Direct unit test; real helpers.

Class with injected deps?
  → Construct with port mocks; assert return + necessary port calls.

HTTP route / middleware / action?
  → Mount router or use startTestBackend; mock services; supertest.

Knex / SQL / migrations?
  → TestDatabases (+ migrate). Not Knex mocks for SQL truth.

External provider?
  → Mock HTTP client (or msw at client layer); assert metric/IDs/values.

React presentational UI?
  → render + screen; mock data hooks and heavy viz.

Hook wrapping useApi / react-query?
  → renderHook; mock the network/API seam; assert mapped state.

NFS extension / blueprint?
  → createExtensionTester / renderInTestApp / mockApis.
```

## Create workflow

1. Open the source file; list inputs, outputs, side effects, dependencies.
2. Classify each dependency: keep real vs fake vs mock (see SKILL mock policy).
3. Place test file: colocated `*.test.ts(x)`, or package `__tests__/` if that is the dominant convention.
4. Add Apache header and `describe` matching siblings when the package uses them.
5. Build fixtures with override-friendly helpers; avoid pasting large domain objects into every `it`.
6. Write cases in skill case order (error → default → happy → edge → port).
7. Assert outcomes first; add port `toHaveBeenCalledWith` only when orchestration is the job.
8. Run filtered Jest for that file/pattern; fix failures without broadening mocks into pure code.

## Update / refactor workflow

1. Characterize current behaviors that must remain green (especially public contracts).
2. Identify weak patterns: internal spies, private API access, duplicated fixtures, call-count-only tests.
3. Restore real pure helpers; delete spies that duplicate return-value proof.
4. Replace inline blobs with `__fixtures__` / `test-utils` builders.
5. Split overloaded `it` blocks into one-behavior tests.
6. Keep asserts on stable IDs, config paths, status codes, and response shapes.
7. Re-run filtered tests; confirm a private rename would not force unrelated edits.

### Success criterion

Production refactors of private helpers do not force test churn; real behavior changes still fail tests.

## Anti-patterns (detail)

| Anti-pattern | Why | Prefer |
|--------------|-----|--------|
| Spy on pure type-guard/mapper as main proof | Couples to internals | Keep helper real; assert throw/return |
| `(obj as any).privateMethod` | Breaks encapsulation | Public API only |
| Export-is-defined as only plugin test | Near-zero signal | One wiring/behavior test or skip |
| Mock every local import | Mock theater | Mock ports only |
| UI: CSS classname / color / exact English locale | Brittle; fights i18n | Role, text from keys, testid, state |
| Claim SQL coverage with mocked Knex | False confidence | `TestDatabases` |
| `import { ConfigReader } from '@backstage/config'` in unit tests | Not the test-utils path | `mockServices.rootConfig({ data })` from `@backstage/backend-test-utils` |

Port interaction **is** valid:

```ts
expect(loader.loadX).toHaveBeenCalledWith(entityRefs, metricId, 'sum', filter);
```

That asserts a boundary contract, not an internal helper.

## Running tests in rhdh-plugins

1. Resolve `workspaces/<name>/` from the path under test.
2. Read `workspaces/<name>/AGENTS.md` when present for workspace-specific commands.
3. Follow `rhdh-workspace` for install/build location (workspace root).
4. Filter unit tests — never whole-monorepo unfiltered Jest.

Examples:

```bash
cd workspaces/<name>
CI=true yarn test --watchAll=false -- --testPathPattern=MyUnit

cd workspaces/<name>/plugins/<package>
yarn test MyUnit
```

## Fixture conventions (adopt when useful)

- Package-level `__fixtures__/mock*.ts` with `mockX(overrides?)` or fluent builders
- Frontend `src/test-utils/` for shared render/translation helpers
- Prefer typed builders over repeated `as unknown as` casts in every test

Scorecard illustrates builders well under `plugins/*/__fixtures__/`; do not treat its spy-heavy suites as the standard.
