# ADR-0005: External Secrets Operator with AWS Secrets Manager

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
Kubernetes Secrets are only base64. Committing them (even encrypted) couples secret rotation to Git history.

## Decision
Terraform creates the secret values in Secrets Manager; the RDS master password is generated and rotated by RDS itself. ESO, authenticating through IRSA with a policy scoped to specific secret ARNs, syncs them into Kubernetes Secrets. Git only contains `ExternalSecret` references.

## Consequences
No secret values in Git or in container images; rotation happens at the source; access is auditable in CloudTrail. Costs: another operator and IAM wiring, secrets are still plain Kubernetes Secrets inside the cluster (encrypted at rest with a KMS key), and pods read env vars at start, so rotation needs a restart (Stakater Reloader is the planned fix).

## Alternatives considered
Sealed Secrets (simple, but encrypted blobs in Git and manual rotation); SOPS (similar); mounting secrets with the CSI driver (no Kubernetes Secret object, but more complex).
