# GitHub configuration

Pipelines authenticate to AWS with OIDC, so there are **no secrets to store**, only variables and
protection rules.

## Repository variables (Settings -> Secrets and variables -> Actions -> Variables)

| Variable | Value | Used by |
|---|---|---|
| `AWS_CI_ROLE_ARN` | `terraform -chdir=terraform/bootstrap output github_ci_role_arn` | ci, promote |
| `TF_PLAN_ROLE_ARN` | `... output terraform_plan_role_arn` | terraform-plan, drift |
| `TF_APPLY_ROLE_ARN` | `... output terraform_apply_role_arn` | terraform-apply |
| `TF_STATE_BUCKET` | `... output state_bucket` | all Terraform workflows |
| `TF_PUBLIC_ACCESS_CIDRS` | JSON list, e.g. `["203.0.113.10/32"]` (non-prod API access) | plan/apply/drift |
| `TF_PUBLIC_ACCESS_CIDRS_PROD` | JSON list for the prod API endpoint (never `0.0.0.0/0`) | terraform-apply (prod) |
| `STAGING_URL` | `https://staging.<domain>` | promote (smoke test) |

## Environments (Settings -> Environments)

| Environment | Required reviewers | Why |
|---|---|---|
| `staging` | none (optional) | Target of dev -> staging promotion |
| `production` | **yes** | Gates the production promotion job |
| `nonprod-infra` | yes (recommended) | Only this environment can assume the Terraform apply role for non-prod |
| `production-infra` | **yes** | Same for prod. Names must match `apply_environments` in `terraform/bootstrap/variables.tf` |

## Repository settings

- **Actions -> General -> Workflow permissions:** allow "Read and write", and tick **Allow GitHub Actions to create and approve pull requests** (the promote workflow opens PRs).
- **Branch protection on `main`:** require PR review and the status checks from `CI`; require linear history. The dev tag-bump commit is pushed directly to `main` by `github-actions[bot]`, so either allow that actor to bypass for this path, or switch the bump to a GitHub App token / deploy key.
- **CODEOWNERS** (recommended): require platform-team review for `terraform/`, `gitops/clusters/`, `gitops/environments/production/` and `.github/`.
- **Secret scanning and push protection:** enable (the repo should never contain secrets).

## Trust boundaries worth understanding

| Role | Who can assume it | Powers |
|---|---|---|
| ci | any workflow in this repo (`repo:ORG/REPO:*`) | push images to ECR only |
| terraform-plan | pull_request events and `main` | `ReadOnlyAccess` + state access |
| terraform-apply | jobs targeting `nonprod-infra` / `production-infra` environments | Administrator (compensated by approvals, CloudTrail) |

The CI role's trust policy is deliberately broad (any ref), because pushing an immutable, scanned image
is low risk; the dangerous role is gated by environment approval. Tighten the `sub` to `ref:refs/heads/main`
if you only build from main.
