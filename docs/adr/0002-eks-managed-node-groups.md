# ADR-0002: EKS managed node groups now, Karpenter later

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
Workers need patching, scaling and replacement. Options range from self-managed ASGs to Karpenter and Fargate.

## Decision
Two managed node groups per cluster: a small on-demand `system`/`core` group and a Spot group for stateless apps (several instance types to widen Spot pools). Production adds a tainted Spot `burst` group scaled from zero. Karpenter is **not** installed; subnets are already tagged `karpenter.sh/discovery` so adopting it is additive.

## Consequences
Managed groups give rolling AMI upgrades, drain-on-terminate and no extra controller to operate, which is the right trade for a small team. Costs: scaling is group-granular (less efficient bin-packing than Karpenter) and `desired_size` is ignored by Terraform so the autoscaler owns it. Without Cluster Autoscaler/Karpenter, nodes scale only between min and max if something changes desired capacity; installing one is the first scalability follow-up.

## Alternatives considered
Karpenter (better cost and speed; deferred to keep the first version understandable); Fargate (no DaemonSets, higher per-pod cost, poor fit for node-level agents like Alloy); self-managed nodes (more control, much more toil).
