# ADR-0004: GitOps with ArgoCD, app-of-apps, manual sync in production

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
Deployments should be reviewable, repeatable, auditable and reversible, and CI should not hold cluster credentials.

## Decision
ArgoCD runs in each cluster (installed by Terraform). One hand-applied `root` Application points at `gitops/clusters/<cluster>`, which defines AppProjects, platform config, third-party tooling (ApplicationSet) and workloads (ApplicationSet over a single Helm chart). CI only edits an image tag in Git. dev/staging auto-sync with self-heal and prune; production has no `automated` block, so a human syncs it.

## Consequences
Rollback is `git revert`; drift is reverted automatically; there is a full audit trail; CI never talks to the cluster. AppProjects stop workloads from creating cluster-scoped resources. Costs: ArgoCD itself is a critical component (it is installed by Terraform, not by itself), ApplicationSet-generated apps are eventually consistent rather than strictly ordered, and the repo credentials for a private repo must be provisioned.

## Alternatives considered
Flux (equally valid; ArgoCD's UI and ApplicationSets suited the demo); push-based `helm upgrade` from CI (needs cluster credentials in CI, no drift correction).
