# ADR-0001: Terraform remote state with S3 + DynamoDB, and OIDC for CI

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
Terraform needs shared, locked state, and CI needs AWS access. Long-lived access keys in GitHub secrets are the most common way cloud accounts get compromised.

## Decision
State lives in a versioned, encrypted, private S3 bucket with a DynamoDB lock table, created by a tiny `bootstrap` stack that uses local state once. CI authenticates with GitHub OIDC: three roles (image push, read-only plan, apply). The apply role can only be assumed from GitHub Environments that carry required reviewers.

## Consequences
No static credentials exist anywhere. Plans on pull requests are read-only, so a malicious PR cannot change AWS. State has versioning for rollback and a lock against concurrent applies. Costs: the apply role is effectively AdministratorAccess (Terraform creates IAM, VPC, EKS), mitigated by approval + branch protection + CloudTrail; a real organisation adds a permissions boundary and SCPs. Terraform 1.10+ can lock with S3 alone (`use_lockfile`), making DynamoDB optional; it is kept here because it works on every version.

## Alternatives considered
Terraform Cloud/Spacelift (less to run, but another vendor and cost); access keys in secrets (rejected: unrotated long-lived credentials); a single admin human applying from a laptop (no audit trail, not reproducible).
