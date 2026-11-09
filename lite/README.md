# Lite edition: run the platform for $0 to ~$0 on AWS Free Tier (or on your laptop)

The full edition (EKS, NAT gateways, Multi-AZ RDS, ElastiCache, ALB) costs roughly
$190-260/month even for non-prod, and **none of it is free-tier**. This edition keeps the
parts that make the project worth showing (GitOps with Argo CD, the same Helm chart,
NetworkPolicies, Pod Security, CI with Trivy, migrations as hooks) and swaps the
expensive managed services for cheap equivalents.

| Concern | Full edition | Lite edition |
|---|---|---|
| Kubernetes | EKS (~$73/mo control plane, **not free**) | k3s on one VM, or k3d on your laptop |
| Database | RDS Postgres Multi-AZ | PostgreSQL StatefulSet (`lite/gitops/platform`) |
| Cache / queue | ElastiCache | Redis StatefulSet |
| Ingress | ALB + ACM | Traefik (bundled with k3s), plain HTTP |
| Registry | ECR | GHCR (free for public repos) |
| Secrets | Secrets Manager + External Secrets | Generated in-cluster by the bootstrap script |
| CI auth | GitHub OIDC to AWS | `GITHUB_TOKEN` to GHCR |
| Monitoring | Prometheus, Grafana, Loki, Tempo, Alertmanager | Optional trimmed Prometheus + Grafana |
| Policy | Kyverno | Pod Security `restricted` only |
| HA / backups | Multi-AZ, PITR, DR runbook | **None** (single node, see "What you give up") |

## Option A: local, $0 (k3d)

Needs Docker, [k3d](https://k3d.io), kubectl and openssl. The cluster pulls manifests from
GitHub, so push your repo first.

```bash
# 1. Make the repo public on GitHub (free GHCR + Actions), then fill in your org/repo
GITHUB_ORG=acme GITHUB_REPO=eks-platform lite/scripts/configure.sh
git add -A && git commit -m "configure lite" && git push

# 2. Scaffold the Laravel app once, commit it (see apps/backend/README.md)
scripts/scaffold-backend.sh && git add apps && git commit -m "backend" && git push
#    ...this also triggers .github/workflows/ci-lite.yaml (see "CI" below)

# 3. Create the cluster and bootstrap everything
lite/scripts/local-up.sh        # app on http://localhost:8080
lite/scripts/smoke-test.sh      # once the first image is deployed
lite/scripts/local-down.sh      # delete it all
```

## Option B: one free-tier-eligible EC2 instance

```bash
# 0. Same steps 1-2 as above, then pick an instance type YOUR account's plan allows:
aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true \
  --query 'InstanceTypes[].InstanceType' --output text

cd terraform/lite
terraform init
terraform apply -var github_org=acme -var github_repo=eks-platform \
  -var instance_type=c7i-flex.large -var budget_email=you@example.com
```

Terraform creates one VPC with a single public subnet (no NAT), one instance, an Elastic IP,
an SSM role (no SSH, no open port 22) and optionally a $5 AWS Budget alert. First boot installs
k3s and runs the same bootstrap script as the local path (about 5-8 minutes):

```bash
terraform output ssm_session_command        # shell on the node, then:
sudo tail -f /var/log/lite-bootstrap.log
terraform output app_url                    # http://<elastic-ip>
lite/scripts/smoke-test.sh "$(terraform output -raw app_url)"
terraform destroy                           # when you are done
```

### What is actually free? (checked 2026-11, verify in your console)

- **Accounts created on or after 2025-07-15** get the *free plan*: $100 credit at sign-up, up to
  $100 more for completing activities, valid up to 6 months or until credits run out. Free-plan
  EC2 types: `t3.micro`, `t3.small`, `t4g.micro`, `t4g.small`, `c7i-flex.large`, `m7i-flex.large`.
  After the plan ends you must upgrade to a paid plan or the account closes.
- **Older accounts** get 12 months of 750 hours/month of `t2.micro`/`t3.micro` (1 GB: too small for
  this stack) and 30 GB of EBS.
- ECR, load balancers, **EKS, NAT gateways and RDS Multi-AZ are not free** (credits only, if at all).
  That is why this edition avoids them.
- A public IPv4 address (including the Elastic IP) costs about $0.005/hour outside free usage.
- Whatever your plan, create an **AWS Budget** (the Terraform does it if you pass `budget_email`)
  and look at Billing weekly. Stop the VM when idle: `terraform output stop_command`.

I could not verify exact monthly hour/GB limits from AWS pages, so treat the numbers above as
"read the Free Tier page for your account" rather than gospel.

## CI (GHCR)

`.github/workflows/ci-lite.yaml` builds both images, scans them with Trivy, pushes
`ghcr.io/<org>/<repo>/{backend,frontend}:<sha>` and commits the new tag to
`lite/gitops/values/*.yaml`; Argo CD syncs that commit. Things to know:

1. Disable the full edition's `CI` workflow on a lite fork (it assumes AWS): *Actions -> CI -> Disable*.
2. New GHCR packages are **private**. Either make them public (package settings), or give the
   cluster a pull secret: `GHCR_USER=you GHCR_TOKEN=<PAT with read:packages> lite/scripts/bootstrap-cluster.sh`
   (re-running is safe).
3. Until the first image exists, backend/worker/frontend sit in `ImagePullBackOff`. That is expected.
4. Actions *Settings -> Actions -> Workflow permissions* must be "Read and write".

## Optional: monitoring

On a 4 GB node only: see the header of `lite/gitops/optional/monitoring.yaml` (3 commands).
It installs Prometheus + Grafana with 3-day retention. The SLO rules in `monitoring/prometheus/rules`
can be applied on top if you want the burn-rate alerts without Alertmanager delivery.

## Resource budget (rough, 4 GB node)

| Component | RAM |
|---|---|
| k3s + Traefik + CoreDNS + metrics-server | ~600 MB |
| Argo CD (core mode) | ~400 MB |
| Postgres + Redis | ~350 MB |
| backend + worker + frontend (1 replica each) | ~500 MB |
| **Total without monitoring** | **~1.9 GB** |
| Optional Prometheus + Grafana | +~1.2 GB |

On a 2 GB instance it only fits without monitoring and with swap (Terraform adds 2 GB by default).

## What you give up (be honest about it in an interview)

- **No high availability**: one node, one replica each. Node reboot = downtime.
- **Only same-node backups**: a nightly `pg_dump` CronJob keeps 7 dumps on a second volume
  (`lite/gitops/platform/backup.yaml`). That survives a bad migration, not losing the VM; copy
  dumps off the node (e.g. `aws s3 cp`) for real durability. Restore:
  `gunzip -c app-<date>.sql.gz | psql -h postgres -U app app` from a pod in `data`.
- **No TLS**: plain HTTP on the IP. Add cert-manager and a domain (or `<ip>.sslip.io`) to fix.
- **Secrets are generated and kept only in the cluster**, not in a secrets manager. Losing the
  VM loses the keys (and the data they protect).
- **Uploads are ephemeral** (`FILESYSTEM_DISK=local`): fine for a demo, wrong for production.
- **Not validated against a real cluster**: like the rest of this project, the lite files were
  checked for syntax and value layering only (see the root README, "Validation status").
  Expect to debug the first run.

## Layout

```
lite/
  gitops/
    bootstrap/   namespaces + root Application (applied once by the script)
    clusters/    AppProjects, data app, workloads ApplicationSet (watched by root)
    platform/    Postgres, Redis, NetworkPolicies
    values/      lite overrides for the shared Helm chart (image tags live here)
    optional/    monitoring (move into clusters/ to enable)
  monitoring/    trimmed kube-prometheus-stack values
  scripts/       configure.sh, bootstrap-cluster.sh, local-up.sh, local-down.sh, smoke-test.sh
terraform/lite/  single-VM stack (VPC, EC2, SSM, EIP, budget)
.github/workflows/ci-lite.yaml
```
