# Interview preparation

How to use this: read the question, answer **out loud** in your own words, then compare with the
points below. Every answer points at a real file so you can say "let me show you". If you cannot
explain a file you would be shown, go back to `docs/learning-path.md`.

## The 2-minute pitch

> "I built a production-style platform on AWS EKS. Terraform provisions a three-tier network, the
> cluster, and a hardened data tier, in two layers with separate state. Applications ship through
> GitOps: CI builds, scans with Trivy and pushes immutable images, then changes one line in Git;
> ArgoCD deploys. Dev and staging auto-sync; production is a manual sync with a canary that
> Prometheus judges, and it rolls back on its own. Secrets never touch Git: External Secrets pulls
> them from Secrets Manager using IRSA. Observability is Prometheus, Loki and Tempo with SLO
> burn-rate alerts, and I run chaos experiments in dev to verify the reliability claims. I wrote
> ADRs for every major decision, including what each one costs."

**Always volunteer the limits:** it has not been load-tested at scale; Prometheus is single-replica;
there is no cross-region DR; the canary is replica-weighted rather than traffic-weighted. Naming
gaps *and* what you would do next reads as seniority.

---

## Infrastructure as code

**Why a separate bootstrap stack for state?** State storage must exist before Terraform can use it,
so a tiny stack with local state creates the bucket, lock table and CI roles once. Everything else
uses the remote backend. (`terraform/bootstrap/`)

**Why split Terraform into layers and states?** The Helm provider must reach the cluster at *plan*
time; in a single apply that creates the cluster it cannot. Layers also shrink the blast radius:
re-applying controllers cannot touch the database. (ADR-0012, `terraform/addons/`)

**Modules vs environments?** Modules are reusable and contain no environment values; environments
only wire modules with inputs. Prod and non-prod therefore differ only by inputs (`environments/prod/main.tf`
documents each difference and why).

**How do you stop two people applying at once / corrupting state?** DynamoDB locking, versioned state
bucket, one state per environment, applies only from CI behind an approval gate with `concurrency`.

**How do you handle secrets in Terraform?** The RDS master password is generated and rotated by RDS
(`manage_master_user_password`), so it is never in code or state. The Redis AUTH token *is* in state
(encrypted bucket, restricted access). I would call that out and rotate it deliberately.

**What would you do about drift?** A weekly scheduled plan opens an issue when it is non-empty
(`.github/workflows/terraform-drift.yaml`), plus restricting console write access.

## Networking

**Walk me through the VPC.** Three tiers per AZ: public (ALBs, NAT), private (nodes and pods, /19 because
the VPC CNI gives every pod a VPC IP), data (RDS/Redis, with **no default route**, so even a wrong
security-group rule cannot give the database internet). S3 gateway endpoint keeps image-layer
traffic off the NAT. (`terraform/modules/vpc/main.tf`)

**Why one NAT in non-prod and three in prod?** Cost versus failure domain. One NAT is ~$33/month but
an AZ failure cuts egress for everyone; per-AZ NATs remove that coupling.

**How does traffic reach a pod?** Route 53 -> ALB (TLS via ACM) -> pod IP directly (`target-type: ip`)
-> container. Frontend `/` and backend `/api` share one ALB via `group.name`.

## Kubernetes

**Why a memory limit but no CPU limit?** CPU limits throttle with CFS even on idle nodes and add tail
latency; a memory limit gives a clean OOM-kill instead of node pressure. CPU requests still drive
scheduling and the HPA. (`helm/app/values.yaml`)

**Liveness vs readiness vs startup?** Liveness = restart me; it must not check dependencies or a DB
blip restarts every pod at once. Readiness = send me traffic; it may check DB/Redis. Startup gives slow
boots time without loosening liveness. (`apps/backend/overlay/routes/platform.php`)

**What does a PodDisruptionBudget protect against?** *Voluntary* disruptions only: drains, upgrades,
consolidation. It does nothing for crashes or node failures. Prod uses `minAvailable: 2`.

**How does a rolling update avoid downtime?** `maxUnavailable: 0`, readiness gating, a `preStop` sleep so
the ALB deregisters the pod before it dies, and enough `terminationGracePeriodSeconds`.

**How do NetworkPolicies work here?** Namespace default-deny, then each workload's chart-generated policy
allows only DNS, the data tier on 5432/6379, HTTPS egress where needed, and ingress from the VPC CIDR
(ALB) and the `monitoring` namespace. The VPC CNI enforces them (`enableNetworkPolicy`).

**Why does the worker have no inbound rules?** Nothing should call a queue worker; it pulls jobs. An empty
ingress list under a selecting policy means deny-all. (`helm/app/values/worker.yaml`)

**What happens when a node is drained?** PDB limits simultaneous evictions, topology spread keeps replicas on
different nodes/zones, the scheduler places evicted pods elsewhere, readiness holds traffic until ready.

## CI/CD and GitOps

**Why doesn't CI deploy to the cluster?** GitOps: CI would otherwise need cluster credentials. Instead it
edits one image tag in Git and ArgoCD pulls. Rollback is `git revert`, drift is auto-corrected, and every
change is reviewable. (`.github/workflows/ci.yaml`)

**Why scan before pushing?** Build locally, scan, and only then push, so a vulnerable image never lands in the
registry. Trivy fails on fixable CRITICAL/HIGH. ECR scan-on-push is a second opinion.

**Why immutable tags and the git SHA?** The artifact you tested is exactly what you deploy and roll back to;
`latest` makes rollbacks meaningless. Kyverno blocks `latest` anyway.

**How does promotion work?** The same image moves forward: `promote.yaml` copies the tag from one environment
file to the next via a PR. Production adds an Environment approval, a staging smoke test, PR review and a manual
ArgoCD sync, then the canary. Nothing is rebuilt.

**Why a manual sync for production but automatic elsewhere?** A deliberate human gate where the blast radius is
largest, with a sync window as defence in depth. The canary analysis is the automated safety net.

**What is an ApplicationSet and why use one?** A template plus generators that stamps out many Applications. One
definition produces `{backend, worker, frontend} x {dev, staging}` without copy-paste. (`gitops/clusters/*/workloads.yaml`)

**How do DB migrations run safely?** A Sync-hook Job in wave 1, after config/secrets (wave 0) and before pods
(wave 2): once per release, not N-pods-racing. Migrations must be backward compatible so rollbacks work.

## Security

**How do pods get AWS access?** IRSA: a role per workload whose trust policy pins the cluster OIDC `sub` to one
`namespace:serviceaccount`. No keys. The node role carries only kubelet/CNI/ECR permissions. (ADR-0010)

**How do secrets reach pods?** Terraform writes them to Secrets Manager; ESO (IRSA, policy scoped to specific ARNs)
syncs them into Kubernetes Secrets; Git holds only references. Limitation: env vars need a restart on rotation.

**Pod Security Admission vs Kyverno?** PSA is built in and enforces the Kubernetes hardening baseline per
namespace. Kyverno adds organisation rules PSA cannot express: allowed registry, no latest tag, mandatory resources,
no default ServiceAccount. (ADR-0006)

**What stops a compromised pod doing damage?** Non-root, no privilege escalation, dropped capabilities, seccomp, default-deny
networking, a dedicated ServiceAccount with automount off, a scoped IAM role. Known gap: backend root filesystem is not read-only yet
(documented in `helm/app/README.md`).

**Supply-chain security?** Pinned chart versions, scanned images, immutable tags, registry allow-list, provenance attestations.
Next: sign with Cosign and verify in Kyverno (`verifyImages`), generate SBOMs.

## Observability and reliability

**What are your SLOs and why burn-rate alerts?** 99.9% availability and 95% under 500 ms over 30 days. A fixed
threshold either pages for blips or misses slow leaks. Burn rate (14.4x/1h, 6x/6h, 1x/3d, each with a short confirming
window) pages in proportion to how fast the budget is being spent. (`monitoring/slo/README.md`)

**RED vs USE?** RED (Rate, Errors, Duration) for services; USE (Utilisation, Saturation, Errors) for resources. The
dashboard shows RED for the app and USE-style CPU/memory/replicas beside it.

**Why labels cardinality matters?** Using the raw URL as a label would create unbounded series and melt Prometheus. The
middleware labels with the route *template*. (`RecordMetrics.php`)

**How does the canary decide?** Argo Rollouts shifts 25/50/100% and a background analysis queries Prometheus for the
non-5xx ratio; below 99% it aborts and rolls back automatically. The *same* metric feeds the SLO. Limitation: replica-weighted, not exact traffic weights.

**How would you debug a latency spike?** RED dashboard for which route; saturation (CPU, HPA maxed); RDS Performance Insights for slow
SQL; Redis; node pressure; then traces in Tempo for the exact span. (`docs/runbooks/high-latency.md`)

**RPO and RTO?** RPO <= 5 minutes (PITR), RTO ~2 minutes for an AZ loss (Multi-AZ), 30-90 minutes for a restore. Region loss is not
covered, and I say so. (`docs/disaster-recovery.md`)

**What did chaos engineering teach you?** Write real findings here after you run the experiments, for example "CPU-based HPA
ignores latency, so latency chaos does not scale the service". Concrete findings beat claims. (`chaos/README.md`)

## Trade-offs and "what would you change?"

- **Karpenter** instead of managed node groups for better bin-packing and Spot handling (ADR-0002).
- **Exact traffic-weighted canary** through the ALB integration instead of replica weights (ADR-0007).
- **Multi-region DR**: replicate backups cross-region, warm standby, practised failover.
- **S3-backed Loki/Tempo and Mimir/Thanos** (or managed Prometheus) for scale and long retention.
- **Service mesh** for mTLS and traffic policy when the number of services grows.
- **Cosign + SBOM + `verifyImages`**, and Checkov/OPA as blocking CI gates.
- **Separate accounts** (prod, non-prod, backup, security) with SCPs and a permissions boundary on the apply role.
- **external-dns** and **cert-manager** so DNS and certificates are automated.
- **KEDA** to scale workers on queue depth rather than CPU.

## Behavioural angles this project supports

- *Tell me about a trade-off you made.* One cluster vs two, NAT count, Spot for apps but not databases.
- *Tell me about a failure/incident you handled.* Use a chaos experiment or a deliberate break you did from `docs/learning-path.md`.
- *How do you keep a system maintainable?* ADRs, one chart, modules, layered values, runbooks, CI checks that render and lint everything.
- *How do you balance speed and safety?* Auto-deploy dev, gate prod, canary with analysis, error budgets that decide release pace.
