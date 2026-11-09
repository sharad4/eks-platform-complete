# Runbook: High error rate / error budget burn

## Symptoms
Alerts: `ErrorBudgetBurnFast`, `ErrorBudgetBurnSlow`, `ErrorBudgetBurnTicket`. Users are getting 5xx responses.

## Triage
1. Open **Grafana -> Application: RED + SLO**, pick the environment. Which routes fail? Did it start at a specific minute?
2. Did something change? `kubectl -n argocd get applications` (recent sync?) and `git log -5 -- gitops/environments/<env>`. A deploy within the last 30 minutes is the prime suspect.
3. Is it one pod or all? `kubectl -n <env> get pods -l app.kubernetes.io/name=backend` then `kubectl -n <env> logs deploy/backend --tail=100` (or Grafana Loki panel, filter `|= "ERROR"`).
4. Dependencies: `kubectl -n <env> get pods`, readiness failures point at RDS/Redis. Check RDS CPU/connections in CloudWatch and Performance Insights; check ElastiCache.
5. Capacity: is the HPA maxed (`HPAMaxedOut`) or are pods OOM-killed (`ContainerOOMKilled`)?

## Mitigation
- **Bad release (most common):** in production a canary should already have aborted; check `kubectl argo rollouts get rollout backend -n production`. If not, roll back (see `bad-deploy-rollback.md`). In dev/staging revert the promotion commit.
- **Dependency down:** see `database-restore.md`; for Redis, check the ElastiCache event log and failover status.
- **Overload:** raise `autoscaling.maxReplicas` in the environment values via PR, or scale temporarily with `kubectl -n <env> scale`.

## Verify
Error ratio back under 0.1% on the dashboard and the alert resolves. Smoke test passes: `BASE_URL=https://app.<domain> scripts/smoke-test.sh`.

## Follow-up
Write a blameless post-mortem if more than 10% of the monthly budget was spent. Add the missing test/alert that would have caught it earlier.
