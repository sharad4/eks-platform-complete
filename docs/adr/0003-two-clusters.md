# ADR-0003: Two clusters: one shared non-prod, one production

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
Environment isolation versus cost. A cluster per environment costs ~$73/month in control plane alone plus nodes and NAT.

## Decision
Cluster A hosts `dev` and `staging` namespaces; cluster B hosts `production`. Each logical environment still gets its own database, Redis, bucket, secret and IRSA role. Namespaces carry Pod Security `restricted`, default-deny NetworkPolicies and ResourceQuotas. State is separate per cluster.

## Consequences
A cluster-level failure or bad upgrade can never touch production, and prod can run a newer or older Kubernetes version than non-prod to test upgrades first. Costs: dev and staging share a control plane and nodes, so a runaway dev workload can in principle affect staging (quotas limit this) and staging is not a perfect prod replica. A cluster per environment is the upgrade path when the budget allows.

## Alternatives considered
One cluster for everything (cheapest, but production shares a blast radius with experiments); three clusters (cleanest, ~$75-100/month more).
