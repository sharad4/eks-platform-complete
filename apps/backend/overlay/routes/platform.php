<?php

use App\Support\Metrics;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Route;
use Prometheus\RenderTextFormat;

/*
|--------------------------------------------------------------------------
| Platform routes: the contract between the app and the platform
|--------------------------------------------------------------------------
| Loaded WITHOUT the `web` middleware group on purpose: no session, no cookies,
| no CSRF. Probes and scrapers hit these every few seconds, and with the Redis
| session driver a "web" health check would create a session per probe.
*/

// Liveness: "is the process alive?" Must NEVER touch the database or Redis,
// otherwise a dependency outage makes Kubernetes restart every pod at once.
Route::get('/healthz', fn () => response()->json(['status' => 'ok']));

// Readiness: "should I receive traffic?" Checks dependencies; 503 removes the
// pod from the load balancer until they recover.
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

// Prometheus scrape endpoint. Not exposed through the ALB (only /api is routed).
Route::get('/metrics', function () {
    $body = (new RenderTextFormat())->render(Metrics::registry()->getMetricFamilySamples());

    return response($body, 200, ['Content-Type' => RenderTextFormat::MIME_TYPE]);
});

// Smoke-test / frontend demo endpoint, reachable through the ALB at /api/ping.
Route::get('/api/ping', fn () => response()->json([
    'pong' => true,
    'time' => now()->toIso8601String(),
]));
