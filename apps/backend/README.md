# Backend (Laravel)

The platform does not care what the app does, only that it behaves like a good
cloud-native citizen. The contract this chart and the alerts rely on:

| Contract | Endpoint / setting | Why |
|---|---|---|
| Liveness | `GET /healthz` returns 200 with no dependency checks | A DB outage must not make Kubernetes restart every pod |
| Readiness | `GET /readyz` checks DB + Redis, returns 503 on failure | Pod leaves the load balancer while a dependency is down |
| Metrics | `GET /metrics` (Prometheus text format) | RED metrics for SLOs (Phase 5) |
| Logs | JSON to stderr (`LOG_CHANNEL=stderr` + JsonFormatter) | Loki parses fields; no log files in containers |
| Config | Environment variables only | 12-factor; same image in every environment |
| Secrets | Env vars injected from the External Secrets-managed Secret | Nothing sensitive in the image or in Git |
| Port | 8080, non-root | Pod Security `restricted` |

## Bootstrapping the app

```bash
scripts/scaffold-backend.sh      # creates the Laravel app here and applies ./overlay, then:
cd apps/backend && php artisan test
```

The `overlay/` directory is the platform contract as code: `routes/platform.php`
(health, readiness, metrics, `/api/ping`), `RecordMetrics` middleware, a per-pod
`Metrics` registry and feature tests. **The overlay has been syntax-checked only
(`php -l`); it has not been run against a real Laravel install**, so run the tests
before trusting it. The route definitions look like this (see the real file for the full version):

## Minimal health routes (`routes/platform.php`)

```php
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Route;

Route::get('/healthz', fn () => response()->json(['status' => 'ok']));

Route::get('/readyz', function () {
    try {
        DB::select('select 1');
        Redis::connection()->ping();
        return response()->json(['status' => 'ready']);
    } catch (\Throwable $e) {
        report($e);
        return response()->json(['status' => 'unavailable'], 503);
    }
});
```

## Metrics (sketch)

`RecordMetrics` (global middleware) records `http_requests_total{method,route,status}` and
`http_request_duration_seconds_bucket`, and `/metrics` renders them. The registry uses
**APCu** (shared memory across the php-fpm workers of ONE pod). That is deliberate:
Prometheus scrapes each pod and sums across pods, so per-pod storage is the correct
scope; a shared Redis registry would blend pods together and break `rate()`.
These exact metric names drive the SLO rules, alerts, dashboards and canary analysis.

## Database migrations

Never run migrations from the container entrypoint (N pods race each other).
The chart runs them as an ArgoCD **Sync-hook Job (wave 1)**: once per release, after config/secrets exist and before the new pods start (`helm/app/templates/migration-job.yaml`). Keep migrations backward-compatible so rollbacks work.

## Local run

```bash
docker build -t backend:dev .
docker run --rm -p 8080:8080 -e APP_KEY=base64:$(openssl rand -base64 32) backend:dev
curl localhost:8080/healthz
```
