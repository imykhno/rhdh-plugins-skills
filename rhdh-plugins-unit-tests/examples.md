# RHDH plugins unit tests — examples

Good templates only. Prefer these shapes over copying weak existing suites.
See [SKILL.md](SKILL.md) for rules and [reference.md](reference.md) for tooling.

Match the package’s Apache header on new test files. Reuse **builders**, not
spy-heavy suites.

## Pure util + Config

```ts
import { mockServices } from '@backstage/backend-test-utils';
import { buildAggregationConfigFilter } from './buildAggregationConfigFilter';

const kpiData = (filter?: { status: string }) => ({
  scorecard: {
    aggregationKPIs: {
      kpi: {
        title: 'T',
        type: 'sum',
        metricId: 'github.openPRs',
        ...(filter ? { filter } : {}),
      },
    },
  },
});

describe('buildAggregationConfigFilter', () => {
  it('should return {} when filter is absent', () => {
    const config = mockServices
      .rootConfig({ data: kpiData() })
      .getConfig('scorecard.aggregationKPIs.kpi');

    expect(buildAggregationConfigFilter(config)).toEqual({});
  });

  it('should map filter.status when present', () => {
    const config = mockServices
      .rootConfig({ data: kpiData({ status: 'error' }) })
      .getConfig('scorecard.aggregationKPIs.kpi');

    expect(buildAggregationConfigFilter(config)).toEqual({ status: 'error' });
  });
});
```

## Service / strategy (typed port + builder)

Keep pure helpers/mappers **real**. Fake only the next port. New subject per
test.

```ts
type Metric = { id: string; title: string };

type ScalarConfig = {
  id: string;
  type: 'scalar';
  filter?: { status: string };
};

type Loader = {
  loadScalarMetricByEntityRefs: (
    entityRefs: string[],
    metricId: string,
    aggregation: string,
    filter?: { status: string },
  ) => Promise<{ value: number; total: number; timestamp: string }>;
};

const mockMetric = (overrides?: Partial<Metric>): Metric => ({
  id: 'github.openPRs',
  title: 'Open PRs',
  ...overrides,
});

const mockScalarConfig = (overrides?: Partial<ScalarConfig>): ScalarConfig => ({
  id: 'open-prs-sum',
  type: 'scalar',
  filter: { status: 'error' },
  ...overrides,
});

describe('ScalarAggregationStrategy', () => {
  const createLoader = (): jest.Mocked<Pick<Loader, 'loadScalarMetricByEntityRefs'>> => ({
    loadScalarMetricByEntityRefs: jest.fn().mockResolvedValue({
      value: 847,
      total: 42,
      timestamp: '2025-01-01T10:30:00.000Z',
    }),
  });

  it('should throw when config is not scalar', async () => {
    const loader = createLoader();
    const strategy = new ScalarAggregationStrategy(loader, 'sum');

    await expect(
      strategy.aggregate({
        metric: mockMetric(),
        entityRefs: ['component:default/a'],
        aggregationConfig: { id: 'by-status', type: 'statusGrouped' },
      }),
    ).rejects.toThrow(/Expected a scalar aggregation config/);
  });

  it('should return aggregated API result and call loader with port args', async () => {
    const loader = createLoader();
    const strategy = new ScalarAggregationStrategy(loader, 'sum');
    const metric = mockMetric();
    const aggregationConfig = mockScalarConfig();

    const result = await strategy.aggregate({
      metric,
      entityRefs: ['component:default/a'],
      aggregationConfig,
    });

    expect(result).toMatchObject({
      id: aggregationConfig.id,
      status: 'success',
    });
    expect(loader.loadScalarMetricByEntityRefs).toHaveBeenCalledWith(
      ['component:default/a'],
      metric.id,
      'sum',
      aggregationConfig.filter,
    );
  });
});
```

## Legacy router + supertest

Use when `createRouter` exists. Fake auth; assert status + body.

```ts
import request from 'supertest';
import { mockServices } from '@backstage/backend-test-utils';
import { createRouter } from './router';

type CatalogMetricService = {
  getMetrics: () => Promise<Array<{ id: string }>>;
};

describe('createRouter', () => {
  it('should return 200 and body from service', async () => {
    const catalogMetricService: jest.Mocked<CatalogMetricService> = {
      getMetrics: jest.fn().mockResolvedValue([{ id: 'github.openPRs' }]),
    };

    const router = await createRouter({
      catalogMetricService,
      config: mockServices.rootConfig({ data: {} }),
      logger: mockServices.logger.mock(),
      httpAuth: mockServices.httpAuth(),
      permissions: mockServices.permissions(),
    });

    const res = await request(router).get('/metrics');

    expect(res.status).toBe(200);
    expect(res.body).toEqual([{ id: 'github.openPRs' }]);
  });
});
```

## startTestBackend

Use when the unit is a `createBackendPlugin` / backend module.

```ts
import request from 'supertest';
import { mockServices, startTestBackend } from '@backstage/backend-test-utils';
import { myPlugin } from './plugin';

describe('myPlugin', () => {
  it('should return 200 and metrics from the plugin', async () => {
    const { server } = await startTestBackend({
      features: [
        myPlugin(),
        mockServices.rootConfig.factory({ data: {} }),
        mockServices.httpAuth.factory(),
        mockServices.permissions.factory(),
      ],
    });

    const res = await request(server).get('/api/my-plugin/metrics');

    expect(res.status).toBe(200);
    expect(res.body).toEqual(
      expect.arrayContaining([expect.objectContaining({ id: 'github.openPRs' })]),
    );
  });
});
```

## Repository + TestDatabases

```ts
import {
  mockServices,
  TestDatabaseId,
  TestDatabases,
} from '@backstage/backend-test-utils';
import { MyDatabase } from './MyDatabase';
import { migrate } from './migration';

jest.setTimeout(60_000);

describe('MyDatabase', () => {
  const databases = TestDatabases.create({
    ids: ['SQLITE_3', 'POSTGRES_15'],
  });

  async function createSubject(databaseId: TestDatabaseId) {
    const knex = await databases.init(databaseId);
    await migrate(
      mockServices.database.mock({
        getClient: async () => knex,
        migrations: { skip: false },
      }),
    );
    return { knex, db: new MyDatabase(knex) };
  }

  it.each(databases.eachSupportedId())(
    'should insert and read rows on %p',
    async databaseId => {
      const { db } = await createSubject(databaseId);

      await db.createMetricValues([
        {
          metricId: 'github.openPRs',
          value: 1,
          timestamp: '2025-01-01T00:00:00.000Z',
        },
      ]);

      await expect(db.readLatest('github.openPRs')).resolves.toEqual(
        expect.arrayContaining([
          expect.objectContaining({ metricId: 'github.openPRs', value: 1 }),
        ]),
      );
    },
  );
});
```

## HTTP client + MSW

Use when the unit under test is the outbound HTTP client.

```ts
import { http, HttpResponse } from 'msw';
import { setupServer } from 'msw/node';
import {
  mockServices,
  registerMswTestHooks,
} from '@backstage/backend-test-utils';
import { GithubClient } from './GithubClient';

const server = setupServer();
registerMswTestHooks(server);

describe('GithubClient', () => {
  it('should return open PR count from GitHub', async () => {
    server.use(
      http.get('https://api.github.com/search/issues', () =>
        HttpResponse.json({ total_count: 42 }),
      ),
    );

    const client = new GithubClient({
      config: mockServices.rootConfig({ data: {} }),
    });

    await expect(client.getOpenPullRequestsCount('org/repo')).resolves.toBe(42);
  });
});
```

## Provider with injected client

Inject a typed fake. Do not `jest.mock` the client class.

```ts
type GithubClientPort = {
  getOpenPullRequestsCount: (repo: string) => Promise<number>;
};

type Entity = {
  metadata: { annotations?: Record<string, string> };
};

describe('GithubOpenPRsProvider', () => {
  it('should return metric value from client', async () => {
    const client: jest.Mocked<GithubClientPort> = {
      getOpenPullRequestsCount: jest.fn().mockResolvedValue(42),
    };
    const provider = new GithubOpenPRsProvider(client);
    const entity: Entity = {
      metadata: { annotations: { 'github.com/project-slug': 'org/repo' } },
    };

    const results = await provider.calculateMetrics(entity);

    expect(results.get('github.openPRs')).toBe(42);
    expect(client.getOpenPullRequestsCount).toHaveBeenCalledWith('org/repo');
  });
});
```

## Reusable hook

Use only when the hook is reused. Mock the plugin API, not `useQuery`.

```tsx
import { renderHook, waitFor } from '@testing-library/react';
import { TestApiProvider } from '@backstage/test-utils';
import { myApiRef } from './api';
import { useMetric } from './useMetric';

describe('useMetric', () => {
  it('should return mapped metric from the API', async () => {
    const getMetrics = jest.fn().mockResolvedValue([
      { id: 'github.openPRs', title: 'Open PRs' },
    ]);

    const { result } = renderHook(
      () => useMetric({ metricId: 'github.openPRs' }),
      {
        wrapper: ({ children }) => (
          <TestApiProvider apis={[[myApiRef, { getMetrics }]]}>
            {children}
          </TestApiProvider>
        ),
      },
    );

    await waitFor(() => {
      expect(result.current.metric).toEqual({
        id: 'github.openPRs',
        title: 'Open PRs',
      });
    });
  });
});
```

## Presentational component

Mock the data hook. Query by role; drive one interaction with `userEvent`.

```tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MyCard } from './MyCard';
import { useMetric } from './hooks/useMetric';

jest.mock('./hooks/useMetric');

const useMetricMock = useMetric as jest.MockedFunction<typeof useMetric>;

describe('MyCard', () => {
  it('should show an alert when the metric fails to load', () => {
    useMetricMock.mockReturnValue({
      metric: undefined,
      loadingData: false,
      error: new Error('failed'),
    });

    render(<MyCard metricId="github.openPRs" />);

    expect(screen.getByRole('alert')).toHaveTextContent(/failed/i);
  });

  it('should refresh the metric when the retry button is clicked', async () => {
    const user = userEvent.setup();
    const refetch = jest.fn();
    useMetricMock.mockReturnValue({
      metric: { id: 'github.openPRs', title: 'Open PRs' },
      loadingData: false,
      error: null,
      refetch,
    });

    render(<MyCard metricId="github.openPRs" />);

    expect(
      screen.getByRole('heading', { name: 'Open PRs' }),
    ).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: /retry/i }));

    expect(refetch).toHaveBeenCalledTimes(1);
  });
});
```

## NFS extension

```tsx
import { screen } from '@testing-library/react';
import {
  createExtensionTester,
  mockApis,
  renderInTestApp,
} from '@backstage/frontend-test-utils';
import { myExtension } from './plugin';

describe('myExtension', () => {
  it('should render extension output', async () => {
    const tester = createExtensionTester(myExtension);

    await renderInTestApp(tester.reactElement(), {
      apis: [
        mockApis.config({ data: { app: { title: 'Test App' } } }),
        mockApis.translation(),
      ],
    });

    expect(
      await screen.findByRole('heading', { name: 'Expected title' }),
    ).toBeInTheDocument();
  });
});
```
