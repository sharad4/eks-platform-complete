# Runbook: Pods crash-looping, not ready, or OOM-killed

## Symptoms
Alerts: `KubePodCrashLooping`, `KubePodNotReady`, `ContainerOOMKilled`, `WorkerNotRunning`, `BackendDown`.

## Triage
1. `kubectl -n <env> get pods` and note STATUS: `CrashLoopBackOff`, `ImagePullBackOff`, `CreateContainerConfigError`, `Pending`, `OOMKilled`.
2. `kubectl -n <env> describe pod <pod>`: read **Events** at the bottom first.
3. Logs of the crashed container: `kubectl -n <env> logs <pod> --previous`.
4. Match the symptom:
   - `ImagePullBackOff`: tag does not exist in ECR (CI did not finish) or the node role cannot pull. `aws ecr describe-images --repository-name eks-platform/backend --image-ids imageTag=<tag>`.
   - `CreateContainerConfigError ... secret not found`: ExternalSecret not synced (`externalsecret-sync-failure.md`).
   - `OOMKilled` (exit 137): memory limit too low or a leak. Compare the working-set panel with the limit.
   - Rejected by admission: `kubectl get events -n <env>` shows a Kyverno or PodSecurity message naming the rule.
   - Readiness failing: `kubectl -n <env> exec deploy/backend -- curl -s localhost:8080/readyz`; usually DB/Redis connectivity or a NetworkPolicy.
   - `Pending`: not enough capacity or a quota hit (`kubectl describe resourcequota -n <env>`).

## Mitigation
Fix forward through Git (never `kubectl edit` in an ArgoCD-managed namespace: self-heal reverts it). For an urgent rollback revert the commit or use `bad-deploy-rollback.md`.

## Verify
`kubectl -n <env> rollout status deploy/backend` (or the Rollout) finishes; alerts resolve.

## Follow-up
If memory: right-size from the FinOps dashboard. If config: add a test or schema rule to the chart so it fails at render time.
