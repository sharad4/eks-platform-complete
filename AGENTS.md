# AGENTS.md

This repository is a production-style EKS / GitOps platform implementation with Terraform, Helm, ArgoCD, and supporting security / observability tooling. Treat this as a real engineering codebase: prefer small, reviewable changes; keep infra and app concerns separated; and validate changes with the narrowest relevant command.

## Repository map

- `terraform/` — infrastructure layers, modules, and environment wiring.
- `helm/app/` — reusable Helm chart for the platform workloads.
- `gitops/` — ArgoCD app definitions and environment values; this is the deployment source of truth.
- `apps/` — backend and frontend application code.
- `monitoring/`, `security/`, `chaos/` — cluster platform concerns.
- `scripts/` — bootstrap, validation, teardown, and smoke-test helpers.
- `docs/` — ADRs, runbooks, and deployment guidance.

## Working expectations

- Keep changes scoped to the issue at hand.
- Favor existing patterns and repository conventions over introducing new abstractions.
- For infrastructure changes, check the relevant Terraform layer and environment before editing.
- For app or chart changes, ensure the GitOps values and Helm chart inputs remain consistent.
- Do not commit secrets or account-specific values into the repo.

## Validation

Use the smallest practical verification for the change:

- Terraform / infra syntax: `make validate`
- Helm / chart rendering: `make charts`
- Lite stack validation: `make lite-validate`
- Shell script checks: `shellcheck lite/scripts/*.sh` for lite scripts; prefer repo script linting where available
- App/build checks: use the project-specific build commands in the relevant app directory if code is touched there

## Common tasks

- If changing Terraform, inspect `terraform/README.md` and the relevant `terraform/*/` layer before editing.
- If changing deployment manifests or values, inspect `gitops/` and `helm/app/` together.
- If fixing a script, prefer idempotent behavior and clear error handling.
- If updating docs, keep them consistent with the actual repo layout and commands.

## Guardrails

- Do not claim AWS or cluster validation without actual evidence from the environment.
- Call out assumptions when a check could not be run locally.
- Prefer deterministic, explicit configuration over hidden state.
- Preserve compatibility for both the full EKS platform and the lite/local flows unless the task is explicitly scoped elsewhere.
