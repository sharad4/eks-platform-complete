# Deploy from zero

End to end, in order. Times are approximate. **Read the "Before you start" section: several
pieces of this repository could not be executed during authoring, and this guide tells you exactly
where to expect first-run fixes.**

## Before you start

**Needed:** an AWS account (admin access for the first run), a domain in Route 53, a GitHub repository
(this code pushed to `main`), and locally `terraform >= 1.9`, `awscli v2`, `kubectl`, `helm`, `jq`, `git`.

**Cost:** non-prod is roughly $190-260/month if left running, prod $560-830. Deploy, record, then destroy
(`scripts/destroy.sh`). See `docs/cost-optimization.md`.

**Validation status (be aware):**

| Part | Checked | Not checked |
|---|---|---|
| Terraform | Syntax parses (HCL parser) | `terraform validate` / `plan` / `apply` never ran |
| Helm chart | Values and plain YAML parse | `helm lint` / `template` never ran |
| GitHub workflows | `actionlint` clean | Never executed on GitHub |
| Shell scripts | `shellcheck` clean | Not executed against AWS |
| Frontend | `npm install` + `vite build` succeeded | Container build not run |
| Backend overlay | `php -l` syntax only | Not run against a real Laravel install |
| Chart versions | **Guessed**, not verified | Run `scripts/check-versions.sh` |

So: run `make validate` and `make charts` first, expect to fix a typo or a version, and treat the first
apply as a debugging session in **non-prod**.

## 0. Local checks (10 min)
```bash
make validate          # terraform init -backend=false + validate for every stack
make charts            # helm lint --strict + render + kubeconform (needs helm)
scripts/check-versions.sh   # compare pinned chart versions with the latest
```

## 1. Bootstrap state and CI roles (5 min)
```bash
cd terraform/bootstrap
terraform init
terraform apply -var github_org=YOUR_ORG -var github_repo=YOUR_REPO
terraform output
```
Then configure GitHub (see `docs/github-setup.md`): repository **variables** from these outputs,
and the four Environments.

## 2. Non-prod infrastructure (20-30 min)
```bash
cd ../environments/nonprod
cp backend.hcl.example backend.hcl        # bucket + lock table from step 1
cp terraform.tfvars.example terraform.tfvars   # your IP in public_access_cidrs
terraform init -backend-config=backend.hcl
terraform apply
$(terraform output -raw kubeconfig_command) && kubectl get nodes
```
(`scripts/bootstrap.sh nonprod` runs steps 2-3 with prompts.)

## 3. Controllers: ALB, External Secrets, ArgoCD, metrics-server (5-10 min)
```bash
cd ../../addons/nonprod
cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars   # edit the bucket
terraform init -backend-config=backend.hcl && terraform apply
```

## 4. Fill in your values and publish to Git
Requires an ACM certificate per hostname in the same region (dev/staging/app subdomains).
```bash
GITHUB_ORG=you GITHUB_REPO=eks-platform ACCOUNT_ID=123456789012 REGION=us-east-1 DOMAIN=example.com \
CERT_ARN_DEV=arn:aws:acm:... CERT_ARN_STAGING=arn:aws:acm:... CERT_ARN_PRODUCTION=arn:aws:acm:... \
scripts/configure.sh
git add -A && git commit -m "configure environment" && git push
```
It also reads the RDS secret ARNs from Terraform outputs. Any token it reports as unset must be filled before ArgoCD can deploy.

## 5. Platform secrets (2 min)
```bash
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX scripts/create-platform-secrets.sh
```
Re-apply the **addons** layer if you changed Terraform outputs the ESO policy depends on.

## 6. Application code and first images
```bash
scripts/scaffold-backend.sh && (cd apps/backend && php artisan test)   # Laravel + platform overlay
git add apps && git commit -m "add apps" && git push
```
CI lints, tests, builds, Trivy-scans, pushes images to ECR and commits the new tag to
`gitops/environments/dev/*.yaml`. **Do this before step 7**, otherwise pods will sit in `ImagePullBackOff`
on the placeholder tag `initial`.

## 7. Hand the cluster to ArgoCD (the only manual `kubectl apply`)
```bash
# Private repo? register credentials first:  argocd repo add https://github.com/<org>/<repo>.git --username git --password <PAT>
kubectl apply -f gitops/bootstrap/root-nonprod.yaml
kubectl -n argocd get applications -w
```
Expect several minutes of **eventual consistency**: apps that need CRDs from other apps fail once
and retry. Open ArgoCD: `kubectl -n argocd port-forward svc/argocd-server 8080:80`
(password: the addons stack's `argocd_admin_password_command` output).

## 8. DNS and smoke test
```bash
kubectl -n dev get ingress          # ADDRESS is the ALB hostname
```
Create `dev.<domain>` and `staging.<domain>` records (alias/CNAME) pointing at the ALB (or add `external-dns`).
```bash
BASE_URL=https://dev.example.com scripts/smoke-test.sh
```

## 9. See the platform work
- Grafana: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80` (login from `scripts/create-platform-secrets.sh` output). Open **Application: RED + SLO**.
- Break and fix: follow `docs/learning-path.md` labs and `chaos/README.md`.

## 10. Staging, then production
```bash
# GitHub Actions -> Promote -> from=dev to=staging  (opens a PR; merge it; staging auto-syncs)
```
Repeat steps 2-5 for `prod` (`environments/prod`, `addons/prod`, `gitops/bootstrap/root-prod.yaml`), then
Promote `staging -> production`: Environment approval, staging smoke test, PR review, then **sync the app in ArgoCD** and
watch the canary: `kubectl argo rollouts get rollout backend -n production -w`.

## 11. Tear down
```bash
scripts/destroy.sh nonprod
```

## First-run troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `terraform validate` error | Authoring typo or provider schema change | Fix the line it names; re-run `make validate` |
| Helm release fails: chart/version not found | Guessed chart version | `scripts/check-versions.sh`, bump the pin |
| ALB controller `AccessDenied` | IAM policy for a different controller version | Set `alb_controller_policy_ref` to the chart's app version tag |
| Application `unknown field` / `no matches for kind ExternalSecret` | ESO serves `v1`, repo uses `v1beta1` | Change `apiVersion` in the chart value and the ClusterSecretStore |
| `ImagePullBackOff` on tag `initial` | CI has not pushed an image yet | Run step 6 |
| Pods rejected by Kyverno | Registry token not replaced, or a rule violated | Re-run `scripts/configure.sh`; read the admission message |
| Ingress has no address | ALB controller unhealthy or subnet tags missing | `kubectl -n kube-system logs deploy/aws-load-balancer-controller` |
| Grafana pod `CreateContainerConfigError` | `grafana-admin` secret not synced | Step 5, then the ExternalSecret runbook |
| App cannot reach the DB | NetworkPolicy data CIDRs or RDS SG | `docs/runbooks/pod-crashloop.md` |
| CI cannot push | `AWS_CI_ROLE_ARN` variable wrong, or OIDC trust repo mismatch | Check bootstrap outputs and `github_org/github_repo` |
