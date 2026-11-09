# Runbook: Rolling back a bad release

## Symptoms
A release is causing errors or a canary is stuck/aborted.

## Triage
1. Identify the bad change: `git log --oneline -10 -- gitops/environments/<env>`.
2. **Production canary:** `kubectl argo rollouts get rollout backend -n production -w`. If analysis failed it has already aborted and traffic is back on the stable version; confirm with the stable ReplicaSet at full strength.

## Mitigation
- **Preferred (GitOps):** revert the promotion commit (`git revert <sha>`), push or merge the PR. dev/staging sync automatically; in production sync the app, the previous image rolls out through the same canary.
- **Fast manual abort in production:** `kubectl argo rollouts abort backend -n production` then `kubectl argo rollouts undo backend -n production`. ArgoCD will show OutOfSync until Git matches; **revert in Git immediately after**, otherwise a later sync re-applies the bad tag.
- **Database migrations are not rolled back by an image rollback.** Migrations must be backward-compatible (expand, then contract) so the previous version still works against the new schema.

## Verify
Error ratio and latency recover; `kubectl -n production get rollout backend` shows Healthy.

## Follow-up
Add a test for the failure. If the canary did not catch it, tighten the analysis (threshold, add a latency metric).
