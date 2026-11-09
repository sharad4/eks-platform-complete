# Cost optimisation and FinOps notes

Figures are approximate (us-east-1, on-demand, list price at time of writing). Verify with the
AWS Pricing Calculator and Cost Explorer; treat them as order-of-magnitude guidance.

## Where the money goes (typical split, production)

| Component | Share | Notes |
|---|---|---|
| EC2 nodes | 30-40% | The most controllable line |
| NAT gateways (3) + data processing | 15-20% | Fixed hourly + **per-GB**; surprisingly large |
| RDS Multi-AZ | 20-25% | Mostly instance hours |
| EKS control plane | ~10% (fixed $73/mo) | Per cluster; why we run two, not five |
| ALB, ElastiCache, logs, storage | 10-15% | |

## Levers, ordered by effort versus payoff

| Lever | Typical saving | Status in this repo | Trade-off |
|---|---|---|---|
| **Spot for stateless workloads** | 60-70% on those nodes | Done: non-prod `apps` group, prod `burst` group | Interruptions; stateless + PDBs + multiple instance types make it safe. Do **not** put the baseline or databases on Spot |
| **Graviton (arm64)** for RDS/ElastiCache | ~20% | Done for RDS/Redis (`t4g`) | Nodes still x86; moving them needs multi-arch images |
| **Right-size requests** | 20-40% of node cost | FinOps dashboard shows requested vs used | Needs real load data; use VPA in recommendation mode |
| **Scale non-prod down off-hours** | ~60% of non-prod compute | `scripts/nonprod-sleep.sh` | Cold-start in the morning |
| **VPC endpoints** (ECR, STS, Secrets Manager, Logs) | Cuts NAT per-GB cost | S3 gateway endpoint done (free); interface endpoints not yet | Interface endpoints cost ~$7/mo per AZ each, so worth it only above ~100 GB/mo NAT traffic |
| **One NAT in non-prod** | ~$65/mo | Done | Single-AZ egress dependency (acceptable in non-prod) |
| **Shared ALB** (`group.name`) | ~$20/mo per avoided ALB | Done: frontend + backend share one per env | Shared fate |
| **gp3 volumes** | ~20% vs gp2 | Done (`StorageClass gp3`) | None |
| **Lifecycle policies** (ECR, S3, logs, Loki) | Prevents unbounded growth | Done | Shorter history |
| **Savings Plans / Reserved** | 30-40% on steady usage | Not done | Commitment; buy only after 2-3 months of stable usage, sized to the baseline |
| **Karpenter consolidation** | 10-30% | Not done (ADR-0002) | Another component |
| **Smaller observability** | Varies | Short retention (7-15 d) | Less history |

## FinOps habits that matter more than any single trick

1. **Tag everything** (`Project`, `Environment`, `ManagedBy` via provider `default_tags`) and activate them as cost-allocation tags in Billing so Cost Explorer can split spend by environment.
2. **Budgets and alerts:** set an AWS Budget per environment (alert at 80% and at forecasted 100%). A forgotten NAT or a runaway log volume shows up in days, not at month end.
3. **Cost visibility in the cluster:** the *FinOps* dashboard (requested vs used, estimated monthly cost, estimated waste per namespace). For per-team or per-workload allocation at scale, add OpenCost or Kubecost.
4. **Review monthly:** top 5 cost lines, idle resources (unattached volumes, old snapshots, idle ELBs), request-vs-usage outliers.
5. **Make cost a design input:** every ADR in `docs/adr/` lists its cost trade-off.

## Cost of the decisions in this project

| Decision | Extra cost | Buys |
|---|---|---|
| Separate prod cluster | ~$73/mo + nodes + NAT | Blast-radius isolation (ADR-0003) |
| Multi-AZ RDS | ~2x DB instance | ~2 minute AZ failover, RPO ~0 |
| 3 NAT gateways in prod | ~$65/mo more than one | No cross-AZ egress dependency |
| Self-hosted observability | EBS + node CPU/RAM + your time | No per-GB SaaS bill, full control |
| Canary instead of rolling | Brief extra pods during rollout | Automatic rollback |

## Portfolio tip

You do not need to leave this running. Deploy, capture screenshots and a short screen recording
of a canary and an alert firing, then `scripts/destroy.sh nonprod`. A few days of the non-prod
stack costs less than a coffee-shop week.
