# ADR-0012: Separate Terraform states for infrastructure and add-ons

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
The Helm and Kubernetes providers must connect to the cluster at plan time, which is impossible in the apply that creates it.

## Decision
Layer 1 (`environments/<env>`) creates network, cluster and data services. Layer 2 (`addons/<env>`) reads layer 1's outputs through remote state and installs the controllers (ALB controller, ESO, ArgoCD, metrics-server) with Helm. One state per cluster per layer.

## Consequences
No chicken-and-egg failure on a fresh account, a smaller blast radius (re-applying add-ons cannot touch the database), and faster plans. Costs: two applies in order, and an output contract between layers that must be kept stable.

## Alternatives considered
One big root module with `depends_on` (fails on first apply or needs a two-pass apply); managing add-ons only through ArgoCD (then ArgoCD itself and the ALB controller still need a bootstrap path).
