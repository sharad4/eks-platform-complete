# Disaster recovery

What can fail, how long recovery takes, how much data can be lost, and how to
practise it. Targets are for the **production** environment.

## Objectives

| | Target | How it is met |
|---|---|---|
| **RPO** (data loss) | <= 5 minutes | RDS automated backups + transaction logs (point-in-time recovery, 14-day window); Multi-AZ synchronous standby means an AZ failure loses nothing |
| **RTO**, AZ failure | ~2 minutes | Multi-AZ RDS failover, 3-AZ node spread, topology spread constraints, PDBs, ALB across AZs |
| **RTO**, bad release | minutes | Canary auto-abort; otherwise `git revert` |
| **RTO**, database corruption | 30-90 minutes | Point-in-time restore to a new instance, repoint or replay (runbook) |
| **RTO**, whole region | **Not covered today** (hours to a day) | Rebuild from code in another region; see gaps |

## Scenarios

| Scenario | Impact | Recovery |
|---|---|---|
| Pod/node dies | None to brief | Kubernetes reschedules; PDB keeps minimum capacity during drains |
| **One AZ lost** | Capacity -33%, brief DB failover | Multi-AZ RDS fails over; Redis replica promoted; pods already spread; HPA backfills. In prod each AZ has its own NAT gateway, so egress survives |
| Bad application release | Errors | Canary analysis aborts; revert in Git (`bad-deploy-rollback.md`) |
| Bad migration / data corruption | Wrong or lost data | Stop writes, PITR to new instance, repoint or replay rows (`database-restore.md`) |
| Accidental `terraform destroy` / resource deletion | Varies | RDS `deletion_protection` and final snapshot; S3 versioning; state bucket versioning; rebuild the rest from code |
| Bad Terraform change | Varies | Plan on PR + approval; state is versioned in S3 so a corrupt state can be rolled back |
| Cluster unusable (bad upgrade, control-plane issue) | Outage | Create a new cluster from Terraform, bootstrap ArgoCD (`gitops/bootstrap/root-prod.yaml`); workloads redeploy from Git. Data tier is independent of the cluster, so it survives |
| Secret deleted | Pods cannot start | Restore within the recovery window (`aws secretsmanager restore-secret`); re-run Terraform for managed ones |
| Credentials leaked | Compromise | No long-lived keys exist; revoke the session / role trust, rotate Secrets Manager values, review CloudTrail |
| **Region outage** | Total | Gap: see below |

## Why the cluster is "cattle" and the data is "pets"

Everything stateless is reproducible from Git in about an hour (Terraform layer 1, layer 2,
`kubectl apply` the root app). The only things that cannot be recreated from code are the
**data stores**: RDS (backups + PITR), S3 uploads (versioned), Secrets Manager (recovery window).
Protect those and the rest is rebuildable.

## Backups in place

- **RDS:** automated daily snapshot + transaction logs, 14 days (prod), `copy_tags_to_snapshot`, `delete_automated_backups = false`, final snapshot on deletion, deletion protection on.
- **S3 uploads:** versioning with a 30-day noncurrent-version expiry.
- **ElastiCache:** daily snapshots (7 days). Redis is a cache and queue; losing it loses in-flight jobs, not source-of-truth data.
- **Terraform state:** versioned bucket, 90-day noncurrent retention.
- **Git:** the source of truth for everything else.

## Known gaps (be honest about these)

1. **No cross-region copy of backups.** A region loss or account compromise takes the backups with the database. Add `aws_db_instance_automated_backups_replication` (needs a second provider alias and a KMS key in the target region) and S3 cross-region replication. Estimated effort: half a day.
2. **No warm standby region.** Region failure RTO is a rebuild: Terraform in a new region, restore the replicated snapshot, repoint DNS. Practised only on paper.
3. **Production state and backups share one AWS account** with everything else. A production-grade setup separates a locked-down backup account.
4. **Prometheus data is not backed up.** Metrics history is lost with the volume; acceptable for 15-day retention, not for long-term SLO reporting.

## Verification: an untested backup is a hope

| Drill | Frequency | Pass criteria |
|---|---|---|
| PITR restore of staging data to a new instance, run a read query | Quarterly | Restored in under 60 minutes, data readable |
| Kill an AZ's nodes in non-prod (`chaos/`) and watch recovery | Monthly | Error budget impact negligible, pods rescheduled |
| Rebuild non-prod from scratch (`scripts/bootstrap.sh nonprod`) | Twice a year | Green smoke test with no manual fixes |
| Restore a deleted secret | Yearly | Application recovers |

Record each drill (date, time taken, what broke) and fix what it reveals.
