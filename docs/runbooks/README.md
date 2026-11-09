# Runbooks

What to do when an alert fires. Each alert annotation links here. Format: symptoms, triage, mitigation, verify, follow-up.

| Runbook | Typical alerts |
|---|---|
| [High error rate / error budget burn](high-error-rate.md) | `ErrorBudgetBurnFast`, `ErrorBudgetBurnSlow`, `ErrorBudgetBurnTicket` |
| [High latency / HPA maxed out](high-latency.md) | `HighLatencyP95`, `HPAMaxedOut` |
| [Pods crash-looping, not ready, or OOM-killed](pod-crashloop.md) | `KubePodCrashLooping`, `KubePodNotReady`, `ContainerOOMKilled`, `WorkerNotRunning`, `BackendDown` |
| [ExternalSecret not syncing](externalsecret-sync-failure.md) | `ExternalSecretSyncFailing` |
| [Nodes full, pods Pending, disks filling](node-capacity.md) | Symptoms: Pending pods, `Insufficient cpu/memory`, `PersistentVolumeFillingUp`, HPA cannot scale |
| [RDS failure or data restore (point-in-time recovery)](database-restore.md) | Symptoms: backend `/readyz` failing, `Multi-AZ failover` events, data corruption or an accidental destructive migration |
| [Rolling back a bad release](bad-deploy-rollback.md) | A release is causing errors or a canary is stuck/aborted |
| [ArgoCD application OutOfSync, Degraded or stuck](argocd-out-of-sync.md) | An Application is not Healthy/Synced, or production shows OutOfSync after a promotion (expected until someone syncs) |

General rules: stabilise first, investigate second; change things through Git; write down what you did (timestamps) as you go.
