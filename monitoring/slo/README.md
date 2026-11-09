# SLIs and SLOs

An **SLI** is a measurement of what users experience. An **SLO** is the target for it.
The gap between 100% and the target is the **error budget**: the amount of failure you
are *allowed*, which turns "is it reliable enough?" from an argument into arithmetic.

| Service | SLI (how it is measured) | SLO | Window | Error budget |
|---|---|---|---|---|
| Backend API availability | Share of requests that are **not 5xx**: `1 - sum(rate(http_requests_total{status=~"5.."})) / sum(rate(http_requests_total))` | **99.9%** | 30 days | 0.1% = **~43 min** of total outage |
| Backend API latency | Share of requests **faster than 500 ms**: `rate(http_request_duration_seconds_bucket{le="0.5"}) / rate(..._count)` | **95%** | 30 days | 5% of requests may be slower |
| Frontend availability | Synthetic check on `/healthz` through the ALB (smoke test / blackbox probe) | 99.9% | 30 days | ~43 min |

## What counts, and what does not

- **4xx responses are not errors.** A 404 or 422 means the client asked for something wrong; the service worked.
- **Health checks and `/metrics` are excluded** from the SLI (the middleware skips them) so probes cannot inflate availability.
- **Planned maintenance counts.** If users cannot use the product, the budget is spent, whatever the reason.

## How the SLO becomes alerts

Defined in `prometheus/rules/slo-rules.yaml`:

| Alert | Burn rate | Long / short window | Severity | Meaning |
|---|---|---|---|---|
| `ErrorBudgetBurnFast` | 14.4x | 1h / 5m | critical (page) | 2% of the monthly budget gone in an hour |
| `ErrorBudgetBurnSlow` | 6x | 6h / 30m | critical (page) | 5% of the budget gone in six hours |
| `ErrorBudgetBurnTicket` | 1x | 3d / 6h | warning (ticket) | Steady leak that will exhaust the budget |

*Burn rate* = observed error ratio / allowed error ratio (0.001). At 1x you use the budget exactly as the
window ends; at 14.4x it would be gone in about two days.

## What to do with the budget

| Budget state | Action |
|---|---|
| Plenty left | Ship features, run chaos experiments, take risks |
| Under ~25% left | Slow down releases, prioritise reliability work |
| Exhausted | Freeze feature releases until the budget recovers (the canary analysis already blocks bad rollouts automatically) |

## The same metric gates deployments

The Argo Rollouts `AnalysisTemplate` (`helm/app/templates/analysistemplate.yaml`) queries the *same*
non-5xx ratio during a canary and aborts below 99%. One definition of "healthy" is used for
dashboards, alerts and releases.

## Dashboards

`Application: RED + SLO` shows rate, errors, duration and the burn rate. `FinOps` shows requested
versus used resources and an estimated monthly cost.
