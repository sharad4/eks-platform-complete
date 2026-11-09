# Terraform

```
terraform/
├── bootstrap/            State bucket, lock table, GitHub OIDC roles  (apply ONCE, local state)
├── modules/              Reusable building blocks (no environment-specific values)
│   ├── vpc/  eks/  rds/  elasticache/  ecr/  iam-irsa/  s3/  secrets/
└── environments/
    ├── nonprod/          dev + staging on one cluster
    └── prod/             production on its own cluster
```

## Apply order

```bash
# 1. Bootstrap (local state, once per AWS account)
cd terraform/bootstrap
terraform init
terraform apply -var github_org=YOUR_ORG -var github_repo=YOUR_REPO
terraform output                       # note state_bucket + lock_table

# 2. Non-prod
cd ../environments/nonprod
cp backend.hcl.example backend.hcl     # fill in bucket + table from step 1
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan && terraform apply tfplan
$(terraform output -raw kubeconfig_command)
kubectl get nodes

# 3. Prod (same steps, in environments/prod)
```

> Expect 15 to 25 minutes for the first EKS apply. RDS Multi-AZ adds a few more.

## Layer 2: platform add-ons (`terraform/addons/`)

A separate state per cluster installs the controllers the cluster needs before
GitOps can take over: **metrics-server, AWS Load Balancer Controller, External
Secrets Operator, ArgoCD**. It is a separate layer because the Helm provider must
reach the cluster at *plan* time, which is impossible in the same apply that
creates it, and it keeps the blast radius small.

```bash
cd terraform/addons/nonprod
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars   # edit bucket name
terraform init -backend-config=backend.hcl
terraform apply
$(terraform output -raw argocd_admin_password_command)
$(terraform output -raw argocd_port_forward)         # UI at http://localhost:8080
```

- Run it as an identity that is cluster-admin (the one that created the cluster, or one in `admin_principal_arns`).
- It needs `aws` CLI on the PATH (the Helm provider calls `aws eks get-token`) and internet access to fetch the ALB controller IAM policy from GitHub at a pinned tag.
- **Chart versions are pinned but were not verified against the live repos** when written. Check them (see `modules/platform-addons/variables.tf`) before the first apply.
- Karpenter is **not** installed yet. Managed node groups scale between min/max. It is an optional later upgrade.

## How the pieces connect

```
vpc ──► eks ──┬─► iam-irsa (backend, later ESO / ALB controller)
   │          └─► cluster SG ──► allowed to reach ──┐
   └─► data subnets ──► rds ───────────────────────┤
                    └─► elasticache ───────────────┘
rds + elasticache ──► secrets (Secrets Manager)  ──► read by External Secrets (Phase 3)
```

## Design notes (interview-ready)

| Topic | Decision | Why |
|---|---|---|
| State layout | One state per environment | A bad apply in nonprod cannot lock or corrupt prod |
| DB password | `manage_master_user_password` | Never in code, state or logs; rotated by RDS |
| Cluster auth | EKS access entries, `API` mode | IAM is the single source of truth; aws-auth ConfigMap is legacy |
| Pod AWS access | IRSA, trust pinned to `namespace:serviceaccount` | A compromised pod elsewhere cannot assume the role |
| Data subnets | No default route | Even a wrong SG rule cannot open a path to the internet |
| Private subnets | /19 | VPC CNI gives every pod a VPC IP; small subnets exhaust fast |
| Node groups | `ignore_changes = desired_size` | The autoscaler owns it at runtime |
| NAT | 1 in nonprod, 1 per AZ in prod | Cost vs. AZ-failure blast radius |
| Image tags | ECR `IMMUTABLE` | What you tested is what you deploy |

## Known limitations (honest list)

- The apply role has AdministratorAccess. Mitigated by environment approval, but a real org adds a permissions boundary and SCPs.
- Redis AUTH token lives in Terraform state (encrypted, access-controlled). Rotating it needs a planned change.
- No cross-region backup copy yet; see the DR doc in Phase 6.
- Only the S3 gateway endpoint exists. Add interface endpoints (ECR, STS, Secrets Manager, CloudWatch Logs) to cut NAT cost further.
- Karpenter is not installed; managed node groups scale via min/max for now (optional later upgrade).
- **Not yet validated with `terraform validate`/`plan`** (see below). Run `make validate` first.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `ResourceInUseException` on access entry | You listed your own identity in `admin_principal_arns` | Remove it; the creator is admin automatically |
| `kubectl` times out | Your IP is not in `public_access_cidrs` | Update the variable and re-apply |
| Pods `Pending`, `Insufficient pods` or no IPs | Subnet exhaustion or node pod limit | Check prefix delegation add-on config; add nodes |
| `InvalidParameterCombination` on RDS | Feature not supported on the instance class (e.g. Performance Insights on t4g.micro) | Adjust `performance_insights_enabled` |
| `BucketAlreadyExists` | S3 names are global | The account ID suffix handles it; change `project` if still clashing |
| Destroy hangs on subnets/VPC | ALB created by the Ingress controller still exists | Delete Ingresses (or the apps) first, wait for the ALB to vanish, then destroy |
| `Error acquiring the state lock` | Previous run crashed | `terraform force-unlock <ID>` after confirming nobody else is applying |
| Secret recreate fails after destroy | Secrets Manager recovery window | Nonprod uses 0 days; for prod use `aws secretsmanager delete-secret --force-delete-without-recovery` deliberately |

## Static checks

```bash
make fmt        # terraform fmt -recursive
make validate   # init -backend=false + validate for bootstrap and both environments
make lint       # tflint + checkov (install separately)
```
