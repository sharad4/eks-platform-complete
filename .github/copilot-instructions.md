# Copilot instructions for this repository

This repo implements a GitOps-driven EKS platform with Terraform, Helm, ArgoCD, and a lite local-mode option. Keep work aligned with that architecture and favor minimal, correct changes.

## Preferred workflow

1. Read the relevant existing file before making a change.
2. Keep infrastructure, chart, and GitOps concerns separated.
3. Validate with the narrowest command that checks the modified behavior.

## Commands to use

- `make validate` — validate Terraform syntax and module layout.
- `make charts` — render and lint the Helm chart assets.
- `make lite-validate` — validate the lite stack and shell scripts.
- `terraform fmt -recursive terraform` — formatting for Terraform files when needed.

## Project-specific guidance

- `gitops/` is the source of truth for deployed configuration.
- `helm/app/` is the reusable chart used by workloads.
- `terraform/` is split into bootstrap, environment, and addon layers.
- `docs/` includes ADRs and runbooks; follow the documented design when touching core platform behavior.
- Do not introduce static AWS account IDs, secret values, or personal environment settings into tracked files.

## Quality bar

- Preserve idempotency in scripts and automation.
- Prefer existing naming and conventions over new abstractions.
- If a check cannot be run in this environment, say so explicitly and include what should be verified elsewhere.
- Keep changes review-friendly and scoped to the requested task.
