# Runbook: High latency / HPA maxed out

## Symptoms
Alerts: `HighLatencyP95`, `HPAMaxedOut`. Requests succeed but slowly.

## Triage
1. **Application: RED + SLO** -> Latency percentiles: all routes or one? If one, suspect that code path or its query.
2. Saturation: CPU and memory per pod panels; replicas available versus HPA desired. At max replicas the autoscaler cannot help.
3. Database: RDS **Performance Insights** top SQL, connection count, CPU credit balance on burstable (`t4g`) instances.
4. Redis: ElastiCache CPU and evictions; a full cache degrades everything that reads it.
5. Node pressure: `kubectl top nodes`, `kubectl describe node | grep -A5 Allocated`; Pending pods mean the cluster is out of capacity (`node-capacity.md`).
6. Noisy neighbour in non-prod: `kubectl top pods -A --sort-by=cpu | head`.

## Mitigation
- Raise `maxReplicas` or the CPU request via PR (requests drive the HPA percentage).
- Scale nodes: temporarily raise the node group desired size (`aws eks update-nodegroup-config`).
- Slow query: add an index or kill the offender (`pg_terminate_backend`) as a stop-gap.

## Verify
p95 below 500 ms for 15 minutes; HPA below max.

## Follow-up
If saturation was the cause, add capacity planning to the backlog. If a query, add it to the slow-query review.
