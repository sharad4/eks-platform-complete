# Runbook: ArgoCD application OutOfSync, Degraded or stuck

## Symptoms
An Application is not Healthy/Synced, or production shows OutOfSync after a promotion (expected until someone syncs).

## Triage
1. `kubectl -n argocd get applications` and `kubectl -n argocd describe application <name>`; the Conditions and the failing resource are listed.
2. Compare: `argocd app diff <name>`.
3. Common causes:
   - **Unknown CRD / `no matches for kind`:** the controller that owns the CRD is not installed yet (ServiceMonitor, Rollout, ExternalSecret). It retries automatically; check the owning Application.
   - **`required: image.tag`:** CI/promotion left the tag empty. Fix the environment values.
   - **Sync wave stuck:** a hook Job (migration) failed: `kubectl -n <env> logs job/backend-migrate`.
   - **Repo access:** `ComparisonError ... authentication required` for a private repo; re-add credentials (`argocd repo add`).
   - **Invalid values:** the Helm render failed; reproduce with `scripts/render-charts.sh`.
   - **Immutable field:** a Job or selector changed; delete the resource and re-sync.
   - **Prod OutOfSync after promotion:** by design. Sync it (UI or `argocd app sync backend-production`) inside the sync window.

## Mitigation
Fix the cause in Git, then `argocd app sync <name>`. Use `--force` or delete only the stuck resource, never the whole Application (the finalizer deletes everything it owns).

## Verify
Application Healthy and Synced; pods running the intended tag.

## Follow-up
If the failure was predictable, add it to CI (`scripts/render-charts.sh`, kubeconform).
