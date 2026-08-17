# RHDH plugins unit tests — reference

Companion to [SKILL.md](SKILL.md). Read when choosing tooling or running a
create/update procedure.

## Layer → tooling

| Layer | Primary tools | Keep real / fake / mock |
|-------|---------------|-------------------------|
| Pure util / mapper / validator | Jest `expect` | Usually nothing; `mockServices.rootConfig` if reading `Config` |
| Service / strategy | Jest + constructor DI | Next-layer ports (`jest.fn` typed fake, `mockServices`) |
| Router (`createRouter`) | `supertest` + Express app | Services behind the route; `mockServices.httpAuth` / `permissions` / config |
| Full backend harness | `startTestBackend` | `mockServices.*.factory()`; features under test |
| Scaffolder action | Invoke action factory/handler | Mock context + ports; assert output + port calls |
| Repository / SQL | `TestDatabases` + migrations | Do not mock Knex for correctness claims |
| Outbound HTTP client | `msw` + `registerMswTestHooks` | Handler rules; reject unmatched traffic |
| Provider wrapping an owned client | Jest + constructor DI | Fake/inject the client; keep provider logic real |
| Frontend API client | Jest | Fake `discoveryApi` / `fetchApi` |
| Reusable hook | `renderHook` + API provider | Plugin API / fetch seam — not `useQuery` |
| Presentational component | `render` + `@testing-library/react` | Data hooks, charts, heavy Backstage chrome |
| Legacy frontend (`createPlugin`) | `renderInTestApp` / `TestApiProvider` from `@backstage/test-utils` | `apis` / mock utility APIs |
| NFS extension | `createExtensionTester`, `renderInTestApp`, `mockApis` from `@backstage/frontend-test-utils` | Extension inputs, utility APIs, `mountedRoutes`. `ExtensionTester.snapshot()` is valid for extension-tree contracts only |

### Packages (typical)

- Backend: `@backstage/backend-test-utils`
- Frontend (legacy): `@backstage/test-utils`
- Frontend (NFS): `@backstage/frontend-test-utils`
- React: `@testing-library/react`, `@testing-library/user-event`, `@testing-library/jest-dom`
- HTTP route asserts: `supertest`
- HTTP stubbing: `msw`

Official docs:

- [Testing with Jest](https://backstage.io/docs/plugins/testing/)
- [Testing Frontend Plugins](https://backstage.io/docs/frontend-system/building-plugins/testing/)
- [Testing Backend Plugins and Modules](https://backstage.io/docs/backend-system/building-plugins-and-modules/testing/)
- [Testing with Utility APIs](https://backstage.io/docs/frontend-system/utility-apis/testing/)
- [mockServices API](https://backstage.io/api/stable/modules/_backstage_backend-test-utils.index.mockServices.html)

## Harness decision

Pick **one** path from the unit under test — do not treat these as interchangeable.

- `createRouter` present → mount the router + `supertest`. Pass
  `mockServices.httpAuth()` and `mockServices.permissions()` (or `.mock()`
  if asserting calls).
- `createBackendPlugin` / backend module → `startTestBackend` +
  `mockServices.*.factory()`.
- HTTP **client** under test → MSW + `registerMswTestHooks` (unmatched
  traffic is rejected).
- Provider wrapping an **owned** client → inject a typed fake (constructor
  DI). `jest.mock` of the class is last resort.
- NFS (`createFrontendPlugin`, extensions) → `@backstage/frontend-test-utils`
  (`renderInTestApp`, `createExtensionTester`, `mockApis`).
- Legacy frontend (`createPlugin`) → `@backstage/test-utils`.
- Scaffolder action → invoke the action factory/handler with a mock
  context; assert output + port calls (same shape as a service test).

## Decision tree

```text
Pure transform / parse / validate?
  → Direct unit test; real helpers.

Class with injected deps?
  → Construct with typed port fakes; assert return + necessary port calls.

createRouter?
  → Mount router; fake httpAuth / permissions / config; supertest.

createBackendPlugin / module?
  → startTestBackend + mockServices.*.factory(); supertest(server).

Knex / SQL / migrations?
  → TestDatabases (+ migrate). Not Knex mocks for SQL truth.

HTTP client talking to an external API?
  → MSW + registerMswTestHooks; assert parsed result.

Provider wrapping an owned client?
  → Inject a fake client; keep provider logic real.

React presentational UI?
  → render + getByRole / userEvent; mock data hooks and heavy viz.

Reusable hook (used in more than one component)?
  → renderHook + API provider; mock getX / fetch, not useQuery.

One-off hook used by a single component?
  → No dedicated hook test; cover it through the component.

NFS extension / blueprint?
  → createExtensionTester / renderInTestApp / mockApis.
  → ExtensionTester.snapshot() only for extension-tree contracts.
```

## mockServices / mockApis patterns

Three usage patterns. Do not `jest.fn()` config, logger, or database when a
fake exists.

**1. Fake instance** — simplified real behavior:

```ts
const config = mockServices.rootConfig({ data: { myPlugin: { enabled: true } } });
const apis = [mockApis.config({ data: { app: { title: 'Test App' } } })];
```

**2. Jest mock** — assert a boundary call:

```ts
const logger = mockServices.logger.mock();
// ...exercise...
expect(logger.error).toHaveBeenCalledWith(expect.stringMatching(/failed/));
```

**3. Factory** — install into a harness:

```ts
await startTestBackend({
  features: [
    myPlugin(),
    mockServices.rootConfig.factory({ data: {} }),
    mockServices.httpAuth.factory(),
    mockServices.database.factory({ knex }),
  ],
});
```

`mockApis.identity()` is a fake; `mockApis.identity.mock()` is a jest mock
for call asserts. Pass either through `renderInTestApp({ apis })`.

## Create workflow

1. Open the source file; list inputs, outputs, side effects, dependencies.
2. Classify each dependency: keep real vs fake vs mock vs factory (see
   SKILL).
3. Read sibling tests for Apache header and `describe` shape only — do not
   copy spies, private-method tests, or mock theater.
4. Place test file: colocated `*.test.ts(x)`, or package `__tests__/` if that
   is the dominant convention.
5. Build fixtures with override-friendly helpers; avoid pasting large domain
   objects into every `it`.
6. Prefer skill case order (error → default → happy → edge → port).
7. Assert outcomes first; add port `toHaveBeenCalledWith` only when
   orchestration is the job.
8. Run filtered Jest for that file/pattern; fix failures without broadening
   mocks into pure code.

## Update / refactor workflow

1. Characterize current behaviors that must remain green (especially public
   contracts).
2. Identify weak patterns: internal spies, private API access, duplicated
   fixtures, call-count-only tests.
3. When touching a spy-heavy file, rewrite the cases you touch; do not add
   a new spy next to old ones.
4. Restore real pure helpers; delete spies that duplicate return-value proof.
5. Replace inline blobs with `__fixtures__` / `test-utils` builders.
6. Split overloaded `it` blocks into one-behavior tests.
7. Keep asserts on stable IDs, config paths, status codes, and response shapes.
8. Re-run filtered tests; confirm a private rename would not force unrelated
   edits.

### Success criterion

A private-helper rename must not force test edits; a real behavior change
must fail tests.

## Anti-patterns (detail)

| Anti-pattern | Why | Prefer |
|--------------|-----|--------|
| Spy on pure type-guard/mapper as main proof | Couples to internals | Keep helper real; assert throw/return |
| `(obj as any).privateMethod` | Breaks encapsulation | Public API only |
| `as any` on a port when a typed fake exists | Hides the contract | `jest.Mocked<Pick<Port, 'method'>>` or a hand-written fake |
| Export-is-defined as only plugin test | Near-zero signal | One wiring/behavior test or skip |
| Mock every local import | Mock theater | Fake/mock ports only |
| `jest.mock` of `useQuery` or `@backstage/core-plugin-api` | Couples to library internals | Provider + plugin API / fetch seam |
| DOM / CSS snapshot | Brittle | `getByRole`; `ExtensionTester.snapshot()` only for extension trees |
| UI: CSS classname / color / exact English locale | Brittle; fights i18n | Role, `mockApis.translation()`, default messages |
| Claim SQL coverage with mocked Knex | False confidence | `TestDatabases` |
| `ConfigReader` from `@backstage/config` | Not the test-utils path | `mockServices.rootConfig({ data })` |

Port interaction **is** valid:

```ts
expect(loader.loadX).toHaveBeenCalledWith(entityRefs, metricId, 'sum', filter);
```

That asserts a boundary contract, not an internal helper.

## Running tests in rhdh-plugins

1. Resolve `workspaces/<name>/` from the path under test.
2. Read `workspaces/<name>/AGENTS.md` when present for workspace-specific
   commands.
3. Install and build from the workspace root (`workspaces/<name>/`).
4. Filter unit tests — never whole-monorepo unfiltered Jest.

Default (from the package):

```bash
cd workspaces/<name>/plugins/<package>
yarn test MyUnit
```

Fallback (workspace root). `CI=true` enables long-running Backstage DB tests:

```bash
cd workspaces/<name>
CI=true yarn test --watchAll=false -- --testPathPattern=MyUnit
```

## Fixture conventions (adopt when useful)

- Package-level `__fixtures__/mock*.ts` with `mockX(overrides?)` or fluent
  builders
- Frontend `src/test-utils/` for shared render/translation helpers
- Prefer typed builders over repeated `as unknown as` casts in every test

Reuse builders; do not treat spy-heavy suites as the standard.
