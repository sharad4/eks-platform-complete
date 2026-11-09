<?php

namespace App\Http\Middleware;

use App\Support\Metrics;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * RED metrics (Rate, Errors, Duration) for every request. These exact names
 * feed the SLO recording rules, alerts, canary analysis and dashboards:
 *
 *   http_requests_total{method,route,status}
 *   http_request_duration_seconds_bucket{method,route,le}
 *
 * The `route` label is the route TEMPLATE (/api/users/{id}), never the raw path.
 * Raw paths would create unbounded label cardinality and melt Prometheus.
 */
class RecordMetrics
{
    private const IGNORED = ['/healthz', '/readyz', '/metrics', '/up'];

    public function handle(Request $request, Closure $next): Response
    {
        $start = microtime(true);
        $response = $next($request);

        $route = $request->route();
        $uri = $route ? '/' . ltrim($route->uri(), '/') : 'unmatched';

        if (in_array($uri, self::IGNORED, true)) {
            return $response;
        }

        $registry = Metrics::registry();

        $registry->getOrRegisterCounter(
            'http', 'requests_total', 'Total HTTP requests', ['method', 'route', 'status']
        )->inc([$request->method(), $uri, (string) $response->getStatusCode()]);

        $registry->getOrRegisterHistogram(
            'http', 'request_duration_seconds', 'HTTP request duration in seconds',
            ['method', 'route'], [0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]
        )->observe(microtime(true) - $start, [$request->method(), $uri]);

        return $response;
    }
}
