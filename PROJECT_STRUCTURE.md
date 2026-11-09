# Project structure

The real tree, annotated. Files marked *(generated)* are produced by a script or filled in by you.

```
eks-platform/
├── README.md                     Overview, architecture diagram, decisions, costs, validation status
├── PROJECT_STRUCTURE.md          This file
├── Makefile                      fmt / validate / charts / plan / apply / lint
├── .github/workflows/
│   ├── ci.yaml                   Lint -> test -> build -> Trivy -> push ECR -> bump dev tag in Git
│   ├── promote.yaml              dev->staging->production: verify image, smoke test, approval, PR
│   ├── terraform-plan.yaml       Read-only plan on PRs, posted as a comment
│   ├── terraform-apply.yaml      Apply on merge, per environment, behind approvals
│   └── terraform-drift.yaml      Weekly plan; opens an issue on drift
│
├── apps/
│   ├── backend/                  Laravel API
│   │   ├── Dockerfile            Multi-stage, non-root, php-fpm + nginx on 8080
│   │   ├── overlay/              Platform contract as code: /healthz /readyz /metrics, RED middleware, tests
│   │   └── README.md             Contract + how to scaffold (scripts/scaffold-backend.sh)
│   └── frontend/                 React (Vite) SPA, nginx-unprivileged, package-lock.json committed
│
├── terraform/
│   ├── README.md                 Apply order, design notes, troubleshooting
│   ├── bootstrap/                State bucket, lock table, GitHub OIDC + 3 roles (apply once, local state)
│   ├── modules/                  vpc  eks  rds  elasticache  ecr  s3  secrets  iam-irsa  platform-addons
│   ├── environments/             LAYER 1: network, cluster, data     (nonprod/  prod/)
│   └── addons/                   LAYER 2: controllers via Helm        (nonprod/  prod/)
│
├── helm/app/                     ONE chart for backend, frontend and worker
│   ├── templates/                deployment rollout analysistemplate migration-job service ingress hpa pdb
│   │                             networkpolicy externalsecret configmap serviceaccount servicemonitor
│   ├── values.yaml               Secure defaults
│   ├── values/                   laravel-common  backend  frontend  worker  none
│   ├── values.schema.json        Input validation
│   └── ci/                       Fake values so lint/template run offline
│
├── gitops/                       What ArgoCD watches (the source of truth)
│   ├── bootstrap/                root-nonprod.yaml, root-prod.yaml  (the only manual kubectl apply)
│   ├── clusters/{nonprod,prod}/  projects, platform-config, platform-tools (ApplicationSet),
│   │                             platform-extras, workloads (ApplicationSet; prod has no auto-sync)
│   ├── platform/                 base/ (ClusterSecretStore, StorageClass), nonprod/ prod/ (namespaces + PSA labels), values/
│   └── environments/{dev,staging,production}/   backend.yaml frontend.yaml worker.yaml  (CI edits image.tag here)
│
├── monitoring/
│   ├── prometheus/               values (+ per-cluster), rules/ (SLO burn rates, alerts), servicemonitors/
│   ├── grafana/dashboards/       RED+SLO and FinOps dashboards as ConfigMaps (generated JSON)
│   ├── alertmanager/             ExternalSecrets for Grafana admin + Slack webhook
│   ├── loki/  alloy/  tempo/     Logs, log shipper, traces
│   └── slo/README.md             SLIs, SLOs, error budgets, burn-rate table
│
├── security/
│   ├── kyverno/                  values + policies/ (registry, latest tag, resources, default SA, labels)
│   ├── network-policies/         default-deny per namespace (nonprod/ prod/)
│   └── quotas/                   ResourceQuota per namespace
│
├── chaos/                        Chaos Mesh values + experiments/ + README (hypothesis-driven game days)
│
├── docs/
│   ├── deploy-from-zero.md  github-setup.md  disaster-recovery.md  cost-optimization.md
│   ├── interview-prep.md  learning-path.md
│   ├── adr/                      12 decision records + index
│   └── runbooks/                 8 incident runbooks + index
│
└── scripts/
    ├── configure.sh              Replace __TOKENS__ with your account/domain/ARNs
    ├── bootstrap.sh              Guided layer 1 -> layer 2 -> root app for one environment
    ├── scaffold-backend.sh       Create the Laravel app and apply the overlay
    ├── create-platform-secrets.sh  Grafana admin + Slack webhook into Secrets Manager
    ├── render-charts.sh          helm lint + template + kubeconform
    ├── check-versions.sh         Pinned vs latest chart versions
    ├── smoke-test.sh             Post-deploy checks
    ├── nonprod-sleep.sh          Scale non-prod down/up out of hours
    └── destroy.sh                Teardown in a safe order
```

## Design principles behind the layout

1. **Separation by rate of change.** Infrastructure (`terraform/`), packaging (`helm/`), desired state (`gitops/`), policy (`security/`) and observability (`monitoring/`) change at different speeds and need different reviewers.
2. **Modules vs environments.** Modules are reusable and value-free; environments only wire them. Prod and non-prod differ by inputs, so they behave alike.
3. **Git is the source of truth.** After one `kubectl apply`, nothing is applied by hand. If it is not under `gitops/`, it is not deployed.
4. **Everything as code.** Dashboards, alerts, policies, quotas and chaos experiments live beside the thing they protect.
5. **Promotion changes one line.** Environment layers live outside the chart, so promoting means changing an image tag.

## Lite edition (free-tier / local)

See `lite/README.md`: `lite/` (GitOps, monitoring, scripts), `terraform/lite/` (single-VM stack), `.github/workflows/ci-lite.yaml`.
