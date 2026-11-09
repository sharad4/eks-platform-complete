# Learning path

Work through the stages in order. Each has: what to **understand** (the concepts, not the commands),
a **lab in this repo** (read it, break it, fix it), and a **checkpoint** question you should be able
to answer without notes. Budget roughly 1-2 weeks per stage part-time; the whole path is a few months.

> The fastest way to learn is to break things deliberately in dev and fix them. The labs say how.

## 1. Networking fundamentals
**Understand:** CIDR and subnet maths, routing tables, internet gateway vs NAT, security groups vs NACLs, DNS, TLS, what an L7 load balancer does, why the VPC CNI gives pods real IPs.
**Lab:** Read `terraform/modules/vpc/main.tf`. Recompute the subnet CIDRs by hand for `10.10.0.0/16`. Change `az_count` and predict the plan before running it.
**Checkpoint:** Why does the data tier have no default route, and what breaks if you give the private subnets a /24 instead of a /19?

## 2. Terraform properly
**Understand:** State (what it is and why it is dangerous), providers, modules, `for_each` vs `count`, `depends_on` vs implicit dependencies, lifecycle (`ignore_changes`, `create_before_destroy`, `prevent_destroy`), remote state data sources, drift.
**Lab:** Run `terraform plan` on `environments/nonprod`, then change an instance class and read the plan. Intentionally edit a resource in the console and watch the next plan show drift. Explain why `desired_size` is in `ignore_changes`.
**Checkpoint:** Why are there two layers of Terraform for one cluster?

## 3. Docker and images
**Understand:** Layers and caching, multi-stage builds, non-root users, why `latest` is harmful, image scanning and what a CVE score means, SBOMs.
**Lab:** Build `apps/frontend` and compare the image size with and without the multi-stage build. Run it as non-root. Run Trivy on it and read a finding end to end.
**Checkpoint:** Why is the migration not run from the container entrypoint?

## 4. Kubernetes core
**Understand:** Pods, ReplicaSets, Deployments, Services, scheduling (requests vs limits, taints, topology spread), probes, rolling updates, HPA, PDB, namespaces, RBAC, ConfigMaps/Secrets.
**Lab:** Render the chart (`scripts/render-charts.sh`, then read `/tmp/rendered/backend.yaml`). Predict what each field does. In dev: break the readiness probe path and watch the rollout stall and why `maxUnavailable: 0` protects you.
**Checkpoint:** What is the difference between liveness and readiness, and why must liveness not check the database?

## 5. Helm
**Understand:** Templates, values layering, helpers, `required`, schemas, hooks, why one chart can serve three workloads.
**Lab:** Add a new optional field (for example `podAnnotations`) with a default, a template change and a schema entry. Render with and without it.
**Checkpoint:** Why are selector labels immutable and what must never go in them?

## 6. IAM, IRSA and secrets
**Understand:** IAM policies (identity vs resource), trust policies, OIDC federation, STS, least privilege, KMS. How a pod turns a projected token into AWS credentials.
**Lab:** Read the trust policy produced by `modules/iam-irsa`. Change the service account name and observe `AccessDenied` from a pod. Break the ESO policy (remove `kms:Decrypt`) and use `docs/runbooks/externalsecret-sync-failure.md` to diagnose it.
**Checkpoint:** Why can a pod in `staging` not assume the `dev` backend role?

## 7. GitOps and CI/CD
**Understand:** Pull vs push deployment, reconciliation loops, drift and self-heal, app-of-apps, ApplicationSets, AppProjects, sync waves and hooks, environment promotion, protected environments, OIDC from CI.
**Lab:** Make a change in `gitops/environments/dev/backend.yaml` and watch ArgoCD deploy it. Use `kubectl edit` on a deployment and watch self-heal revert it. Promote to staging with `promote.yaml`.
**Checkpoint:** A teammate wants to hotfix production with `kubectl`. What happens and what should they do?

## 8. Observability
**Understand:** Metrics vs logs vs traces, cardinality, histograms and percentiles, RED/USE, PromQL (`rate`, `sum by`, `histogram_quantile`), alerting philosophy, SLIs/SLOs/error budgets, burn rates.
**Lab:** Write a PromQL query for the p99 of one route. Generate errors in dev and watch `ErrorBudgetBurnFast` fire and route to Alertmanager. Read `monitoring/prometheus/rules/slo-rules.yaml` and explain the 14.4 factor.
**Checkpoint:** Why do burn-rate alerts use two windows?

## 9. Security
**Understand:** Threat modelling basics, defence in depth, Pod Security Standards, admission control, network segmentation, supply-chain security, secrets lifecycle, least privilege.
**Lab:** Try to deploy a pod that runs as root, uses `:latest`, or pulls from Docker Hub in `dev`; read each rejection. Add a Kyverno rule of your own.
**Checkpoint:** What do PSA and Kyverno each do that the other cannot?

## 10. Reliability and operations
**Understand:** Failure domains (pod, node, AZ, region), RTO/RPO, backups vs replicas, canary vs blue/green, chaos engineering, capacity planning, runbooks, blameless post-mortems.
**Lab:** Run every experiment in `chaos/`, writing the hypothesis first. Do a PITR restore drill from `docs/runbooks/database-restore.md` in non-prod.
**Checkpoint:** What does Multi-AZ protect against, and what does it not (hint: bad deletes, corruption)?

## 11. Cost (FinOps)
**Understand:** The main cost drivers, Spot vs on-demand vs Savings Plans, right-sizing, NAT data charges, tagging and cost allocation.
**Lab:** Open the FinOps dashboard, find the namespace with the lowest CPU efficiency, and propose new requests. Read `docs/cost-optimization.md` and pick the next two levers.
**Checkpoint:** Why is one NAT gateway acceptable in dev but not in prod?

## Suggested reading (find current editions)
- *Site Reliability Engineering* and *The Site Reliability Workbook* (Google): SLOs, alerting on burn rate.
- *Kubernetes in Action* (Marko Luksa), for the mental model.
- The official Kubernetes, EKS Best Practices, Terraform and ArgoCD documentation: read the concept pages, not just the quick starts.
- The AWS Well-Architected Framework (all six pillars); this project touches each of them.
