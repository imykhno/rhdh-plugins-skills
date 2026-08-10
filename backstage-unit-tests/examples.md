# Backstage unit tests — examples

Good templates only. Prefer these shapes over copying weak existing suites.
See [SKILL.md](SKILL.md) for rules and [reference.md](reference.md) for tooling.

Scorecard (and similar packages) may have `__fixtures__` builders — reuse that
**style**, not spy-heavy tests.

## Pure util + Config

```ts
import { mockServices } from '@backstage/backend-test-utils';
import { buildAggregationConfigFilter } from './buildAggregationConfigFilter';

describe('buildAggregationConfigFilter', () => {
  it('should return {} when filter is absent', () => {
    const rootConfig = mockServices.rootConfig({
      data: {
        scorecard: {
          aggregationKPIs: {
            kpi: { title: 'T', type: 'sum', metricId: 'github.openPRs' },
          },
        },
      },
    });
    const config = rootConfig.getConfig('scorecard.aggregationKPIs.kpi');

    expect(buildAggregationConfigFilter(config)).toEqual({});
  });

  it('should map filter.status when present', () => {
    const rootConfig = mockServices.rootConfig({
      data: {
        scorecard: {
          aggregationKPIs: {
            kpi: {
              title: 'T',
              type: 'sum',
              metricId: 'github.openPRs',
              filter: { status: 'error' },
            },
          },
        },
      },
    });
    const config = rootConfig.getConfig('scorecard.aggregationKPIs.kpi');

    expect(buildAggregationConfigFilter(config)).toEqual({ status: 'error' });
  });
});
```

## Service / strategy (port mock + result)

Keep pure helpers/mappers **real**. Mock only the next port.

```ts
describe('ScalarAggregationStrategy', () => {
  const loader = {
    loadScalarMetricByEntityRefs: jest.fn().mockResolvedValue({
      value: 847,
      total: 42,
      entitiesConsidered: 45,
      calculationErrorCount: 3,
      timestamp: '2025-01-01T10:30:00.000Z',
    }),
  };

  const strategy = new ScalarAggregationStrategy(loader as any, 'sum');

  afterEach(() => {
    jest.clearAllMocks();
  });

  it('should throw when config is not scalar', async () => {
    await expect(
      strategy.aggregate({
        metric,
        entityRefs: ['component:default/a'],
        aggregationConfig: statusGroupedConfig,
      }),
    ).rejects.toThrow(/Expected a scalar aggregation config/);
  });

  it('should return aggregated API result and call loader with port args', async () => {
    const result = await strategy.aggregate({
      metric,
      entityRefs: ['component:default/a'],
      aggregationConfig: scalarConfig,
    });

    expect(result).toMatchObject({
      id: scalarConfig.id,
      status: 'success',
    });
    expect(loader.loadScalarMetricByEntityRefs).toHaveBeenCalledWith(
      ['component:default/a'],
      metric.id,
      'sum',
      scalarConfig.filter,
    );
  });
});
```

## Router + supertest

```ts
import request from 'supertest';
import { mockServices } from '@backstage/backend-test-utils';
import { createRouter } from './router';

describe('createRouter', () => {
  it('should return 200 and body from service', async () => {
    const catalogMetricService = {
      getMetrics: jest.fn().mockResolvedValue([{ id: 'github.openPRs' }]),
    };

    const router = await createRouter({
      catalogMetricService: catalogMetricService as any,
      config: mockServices.rootConfig({ data: {} }),
      logger: mockServices.logger.mock(),
      // ...other required deps as mocks
    });

    const res = await request(router).get('/metrics');

    expect(res.status).toBe(200);
    expect(res.body).toEqual([{ id: 'github.openPRs' }]);
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
        /* minimal row */
      ]);

      await expect(db.readLatest(/* … */)).resolves.toEqual(
        expect.arrayContaining([expect.objectContaining({ metricId: 'x' })]),
      );
    },
  );
});
```

## Provider with mocked client

```ts
import { mockServices } from '@backstage/backend-test-utils';
import { GithubOpenPRsProvider } from './GithubOpenPRsProvider';
import { GithubClient } from '../github/GithubClient';

jest.mock('../github/GithubClient');

describe('GithubOpenPRsProvider', () => {
  const Client = GithubClient as jest.MockedClass<typeof GithubClient>;
  const clientInstance = {
    getOpenPullRequestsCount: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    Client.mockImplementation(() => clientInstance as any);
  });

  it('should return metric value from client', async () => {
    clientInstance.getOpenPullRequestsCount.mockResolvedValue(42);
    const config = mockServices.rootConfig({ data: {} });
    const provider = GithubOpenPRsProvider.fromConfig(config);

    const results = await provider.calculateMetrics(entity);

    expect(results.get('github.openPRs')).toBe(42);
  });
});
```

## Hook

```tsx
import { renderHook } from '@testing-library/react';
import { useApi } from '@backstage/core-plugin-api';
import { useQuery } from '@tanstack/react-query';
import { useMetric } from '../useMetric';

jest.mock('@backstage/core-plugin-api');
jest.mock('@tanstack/react-query', () => ({
  ...jest.requireActual('@tanstack/react-query'),
  useQuery: jest.fn(),
}));

describe('useMetric', () => {
  it('should map loading state from useQuery', () => {
    (useApi as jest.Mock).mockReturnValue({ getMetrics: jest.fn() });
    (useQuery as jest.Mock).mockReturnValue({
      isLoading: true,
      error: null,
      data: undefined,
    });

    const { result } = renderHook(() =>
      useMetric({ metricId: 'github.openPRs' }),
    );

    expect(result.current).toEqual({
      metric: undefined,
      loadingData: true,
      error: null,
    });
  });
});
```

## Presentational component

```tsx
import { render, screen } from '@testing-library/react';
import { MyCard } from '../MyCard';

jest.mock('../hooks/useMetric', () => ({
  useMetric: () => ({
    metric: { id: 'github.openPRs', title: 'Open PRs' },
    loadingData: false,
    error: null,
  }),
}));

describe('MyCard', () => {
  it('should render the metric title when data is loaded', () => {
    render(<MyCard metricId="github.openPRs" />);

    expect(screen.getByText('Open PRs')).toBeInTheDocument();
  });
});
```

## NFS extension

```tsx
import { screen, waitFor } from '@testing-library/react';
import {
  createExtensionTester,
  renderInTestApp,
} from '@backstage/frontend-test-utils';
import { myExtension } from './plugin';

describe('myExtension', () => {
  it('should render extension output', async () => {
    const tester = createExtensionTester(myExtension);

    await renderInTestApp(tester.reactElement());

    await waitFor(() => {
      expect(screen.getByText('Expected title')).toBeInTheDocument();
    });
  });
});
```
