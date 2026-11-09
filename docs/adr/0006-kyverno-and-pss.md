# ADR-0006: Pod Security Admission plus Kyverno

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
Preventing insecure or non-compliant workloads from running, cheaply and in a way people can read.

## Decision
Namespaces enforce Pod Security `restricted` (built in, no software to run). Kyverno adds organisation rules PSA cannot express: allowed registry, no `latest` tag, mandatory requests/memory limit, no default ServiceAccount, required labels. Policies are YAML and scoped to the workload namespaces.

## Consequences
Two layers with distinct jobs, both declarative and reviewable in Git. YAML-native rules are quicker to write and audit than Rego. Costs: Kyverno's webhook is on the critical path of pod creation (3 replicas in prod), and complex logic is less expressive than OPA/Rego. Image signature verification (Cosign `verifyImages`) is the next policy to add.

## Alternatives considered
OPA Gatekeeper (more powerful, steeper learning curve); PSA alone (no registry/tag/resource rules); no admission control (rejected).
