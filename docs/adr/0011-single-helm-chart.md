# ADR-0011: One reusable Helm chart for every workload

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
Backend, frontend and worker all need the same production hygiene: probes, security context, HPA, PDB, NetworkPolicy, secrets, ingress.

## Decision
A single `helm/app` chart, driven by layered values (`chart defaults -> shared config -> per-app -> per-environment`). Environment values live in `gitops/environments/`, outside the chart, so promotion means changing an image tag. A schema validates inputs and `required` fails a render with no image tag.

## Consequences
A security or reliability fix lands once for every workload; the three services cannot drift apart. Costs: the chart has many switches, which makes it more abstract than three hand-written charts, and unusual workloads (a StatefulSet, a CronJob) would need new templates.

## Alternatives considered
One chart per service (simple to read, triplicated fixes); Kustomize overlays (no templating, but weaker for this many toggles); a Helm library chart (more indirection).
