# ADR-0007: Argo Rollouts canary gated by Prometheus analysis

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
A rolling update replaces pods regardless of whether the new version is healthy; humans watching dashboards do not scale.

## Decision
In production, an Argo Rollouts `Rollout` references the chart's Deployment (`workloadRef`) and shifts pods 25% / 50% / 100% with pauses. A background `AnalysisTemplate` queries the same non-5xx ratio the SLO uses and aborts and rolls back automatically below 99%.

## Consequences
A bad release is stopped by the metric, not by someone noticing. One definition of healthy for dashboards, alerts and releases. Costs: this is a **replica-weighted** canary (no traffic router), so the traffic split is only approximate and depends on replica counts; exact weights need the ALB traffic-router integration (two Services, weighted target groups). The Deployment sits at 0 replicas as a template holder, which surprises people reading `kubectl get deploy`.

## Alternatives considered
Plain rolling updates (no automatic rollback); blue/green (instant cutover, double capacity); Flagger (comparable, different CRDs).
