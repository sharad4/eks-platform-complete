# Architecture Decision Records

Short, dated-by-number records of *why* each significant choice was made, including what it costs. Interviewers ask "why not X?"; these are the answers.

| ADR | Decision |
|---|---|
| [0001](0001-terraform-state-and-ci-auth.md) | Terraform remote state with S3 + DynamoDB, and OIDC for CI |
| [0002](0002-eks-managed-node-groups.md) | EKS managed node groups now, Karpenter later |
| [0003](0003-two-clusters.md) | Two clusters: one shared non-prod, one production |
| [0004](0004-argocd-gitops.md) | GitOps with ArgoCD, app-of-apps, manual sync in production |
| [0005](0005-external-secrets.md) | External Secrets Operator with AWS Secrets Manager |
| [0006](0006-kyverno-and-pss.md) | Pod Security Admission plus Kyverno |
| [0007](0007-argo-rollouts-canary.md) | Argo Rollouts canary gated by Prometheus analysis |
| [0008](0008-observability-stack.md) | Prometheus, Grafana, Loki, Alloy and Tempo, self-hosted |
| [0009](0009-alb-ingress.md) | AWS Load Balancer Controller (ALB) for ingress |
| [0010](0010-irsa.md) | IAM Roles for Service Accounts (IRSA) for pod AWS access |
| [0011](0011-single-helm-chart.md) | One reusable Helm chart for every workload |
| [0012](0012-terraform-layers.md) | Separate Terraform states for infrastructure and add-ons |

To add one: copy the newest file, bump the number, and keep the four headings (Context, Decision, Consequences, Alternatives). Never edit an accepted ADR to change history; write a new one that supersedes it.
