# Chaos engineering

Chaos engineering is not "break things for fun". It is the scientific method applied to
reliability: **state a hypothesis about steady state, inject a small controlled failure, and
compare reality with the hypothesis.** Every gap you find is a bug you fixed before a real
outage found it.

## Safety rails (why this is safe to run)

- Chaos Mesh is installed **only in the non-prod cluster** (`gitops/clusters/nonprod/platform-tools.yaml`).
- Its controller only acts in namespaces annotated `chaos-mesh.org/inject=enabled`: that is `dev` and nothing else.
- Every experiment has a `duration` or is a `Schedule`, so it cannot run forever.
- Keep Grafana open on **Application: RED + SLO**; if the error ratio exceeds your abort condition, delete the experiment: `kubectl delete -f <file>`.

## The experiments

| File | Injects | Hypothesis | What you learn |
|---|---|---|---|
| `pod-kill-backend.yaml` | Kills one backend pod every 5 min | No user-visible errors | PDB, replicas >= 2, readiness gating, preStop draining all work |
| `network-delay-backend.yaml` | +300 ms latency for 5 min | Latency rises, `HighLatencyP95` fires if sustained | Timeouts/retries, alert thresholds, that CPU-based HPA ignores latency |
| `cpu-stress-backend.yaml` | 90% CPU load for 10 min | HPA scales out, latency recovers | Autoscaler responsiveness and `maxReplicas` headroom |
| `pod-failure-worker.yaml` | Workers unavailable for 2 min | Jobs queue and drain with no loss | Queue durability, `WorkerNotRunning` thresholds |

## Run an experiment (game-day format)

1. **Hypothesis** (write it down before you start).
2. Confirm steady state on the dashboard; check you have error budget left (`monitoring/slo/README.md`).
3. `kubectl apply -f chaos/experiments/<file>.yaml`
4. Watch: `kubectl -n dev get pods -w`, the RED dashboard, and Alertmanager.
5. Remove it (`kubectl delete -f ...`) and wait for recovery.
6. **Record**: did reality match? What alerted, what did not, how long to recover? Turn each surprise into a ticket.

## Ideas for next experiments

- Terminate all nodes in one AZ (`aws ec2 terminate-instances` on that AZ's nodes) and watch spread and recovery.
- `NetworkChaos` partition between the backend and Redis (readiness should pull pods out of rotation, liveness must not restart them).
- Block egress to Secrets Manager and confirm ESO surfaces the failure via `ExternalSecretSyncFailing`.
- Fail over the staging RDS instance (`aws rds reboot-db-instance --force-failover` needs Multi-AZ) and measure the blip.

> Chaos Mesh's chart and CRD fields were written from documentation knowledge and **not run**;
> if `kubectl apply` rejects a field, check `kubectl explain podchaos.spec` for your installed version.
