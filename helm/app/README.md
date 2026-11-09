# `helm/app`: one chart, three workloads

The backend API, frontend and queue worker are all "a containerised process with
config, secrets, scaling and network rules". One chart expresses that once;
three small values files make it each workload. A security fix (say, tighter
`securityContext`) is a one-line change that reaches every service.

> **Status: not yet rendered.** `helm` was not available while this was written,
> so the templates have been proofread but not run through `helm lint` /
> `helm template`. Run `scripts/render-charts.sh` first; fix any typo it finds.

## Values layering

```
values.yaml                         chart defaults (secure, generic)
  └─ values/laravel-common.yaml     config shared by backend + worker
      └─ values/<app>.yaml          backend | frontend | worker
          └─ gitops/environments/<env>/*.yaml   image tag, hostnames, ARNs   (Phase 4)
```

| Workload | Values files (in order) |
|---|---|
| backend | `laravel-common.yaml`, `backend.yaml`, env overrides |
| worker | `laravel-common.yaml`, `worker.yaml`, env overrides |
| frontend | `frontend.yaml`, env overrides |

**Rule:** anything that differs per *environment* lives in the env layer, never in the
chart. That is what makes promotion = "change an image tag in Git".

## What each template does and why

| Template | Production concern it addresses |
|---|---|
| `deployment.yaml` | `maxUnavailable: 0` rolling updates, config checksum rollout, topology spread across AZs and nodes, `preStop` sleep for clean LB draining, probes, restricted security context |
| `service.yaml` | Named port `http` so Ingress, ServiceMonitor and probes reference a name, not a number |
| `ingress.yaml` | ALB via `ingressClassName: alb`; `group.name` lets backend + frontend share **one** ALB (saves ~$20/mo per app) |
| `hpa.yaml` | `autoscaling/v2`, CPU (and optional memory), slow scale-down to avoid flapping |
| `pdb.yaml` | Keeps capacity during node drains and cluster upgrades |
| `networkpolicy.yaml` | Allow-list: DNS, data tier CIDRs on 5432/6379, HTTPS egress; ingress only from the VPC (ALB) and named namespaces |
| `externalsecret.yaml` | References to Secrets Manager, never values. Safe in Git |
| `configmap.yaml` | Non-secret config as env vars; hash triggers rollout on change |
| `serviceaccount.yaml` | IRSA annotation per environment; token automount off |

## Design decisions worth defending

- **Memory limit, no CPU limit.** CPU limits throttle (CFS) and add tail latency even on idle nodes. A memory limit gives a clean OOM-kill instead of node pressure. Requests still drive scheduling and the HPA.
- **Liveness must not check dependencies.** If it did, a Redis blip would restart every pod at once and turn a small problem into an outage. Readiness may check dependencies.
- **`target-type: ip`.** The ALB sends traffic straight to pod IPs: one fewer hop, and health checks reflect the pod. The NetworkPolicy therefore allows the VPC CIDR (the ALB's ENIs), not the node IPs.
- **Selector labels are immutable.** They hold only name + instance; the (changing) version label lives in the general labels. Putting a version in a selector breaks upgrades.
- **Worker shares the backend ServiceAccount.** One IRSA role, one trust policy. Trade-off: the worker inherits the API's S3 permissions. Split them if their needs diverge.
- **`required` on image tag.** A missing tag fails the sync loudly rather than deploying `:latest`.

## Render and lint locally

```bash
brew install helm kubeconform        # or your package manager
scripts/render-charts.sh             # lint --strict + template + schema-check all 3 workloads
```

Manual one-off:

```bash
helm template backend helm/app \
  -f helm/app/values/laravel-common.yaml -f helm/app/values/backend.yaml \
  -f helm/app/ci/test-values.yaml | less
```

## Known gaps / honest TODOs

- **DB username/password are not in the app secret yet.** The `secrets` module publishes host, port, db name and Redis details; the master credentials live in the RDS-managed secret (`db_master_secret_arns` output). Phase 4's env values add them to the ExternalSecret `data:` list, e.g. `{secretKey: DB_PASSWORD, remoteRef: {key: <master secret ARN>, property: password}}` (and `username` -> `DB_USERNAME`). Using the master user for the app is a shortcut; production should create a least-privilege app role via a migration job.
- **ExternalSecret apiVersion.** Newer External Secrets releases serve `external-secrets.io/v1`; `v1beta1` may be deprecated or removed depending on the pinned chart. If ArgoCD reports an unknown version, set `externalSecret.apiVersion` (and update `gitops/platform/base/cluster-secret-store.yaml`).
- **Read-only root filesystem is OFF for backend and worker.** nginx + php-fpm write outside `/tmp` in the base image. Hardening exercise: run once with it ON, read the "read-only file system" errors, add `emptyDir` mounts via `extraVolumes`/`extraVolumeMounts` for exactly those paths, then flip it on.
- **Secret rotation does not restart pods** (env vars are read at start). Add Stakater Reloader, or switch to mounted secret files.
- **Phase 4 changes** `Deployment` to an Argo Rollouts `Rollout` for canary releases; the HPA `scaleTargetRef` then points at the Rollout.
- **Worker scaling is CPU-based.** Queue depth (via KEDA + Redis) is the better signal.
- **Image tags in `values.schema.json` are strings.** CI must quote all-digit SHAs (`"1234567"`) or YAML turns them into integers.

## Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| `image.tag is required` | Env values missing the tag | CI bump step; `helm template ... --set image.tag=x` |
| Pod `CreateContainerConfigError: secret "backend-secrets" not found` | ExternalSecret not synced | `kubectl describe externalsecret backend`; ClusterSecretStore status; IRSA role/policy |
| ExternalSecret `AccessDenied` | ESO role cannot read that secret | Terraform `eso_read_policy_json` lists the ARNs; use the exact name or ARN |
| Pod rejected: `violates PodSecurity "restricted"` | Namespace enforces restricted | Read the message: usually missing `runAsNonRoot` numeric uid, or `seccompProfile` |
| `container has runAsNonRoot and image has non-numeric user` | Image uses `USER name` | Set `podSecurityContext.runAsUser` to the numeric uid |
| Ingress has no ADDRESS | ALB controller not healthy, or subnets untagged | `kubectl -n kube-system logs deploy/aws-load-balancer-controller`; subnet `kubernetes.io/role/elb` tag |
| ALB targets `unhealthy` | NetworkPolicy blocks the ALB, or wrong health path | Policy `ingressFromCidrs` must include the VPC CIDR; check `healthcheck-path` |
| App cannot reach RDS | NetworkPolicy egress or SG | `dataTierCidrs` match the data subnets; RDS SG allows the cluster SG |
| HPA shows `<unknown>/70%` | metrics-server missing or no CPU request | `kubectl top pods`; set `resources.requests.cpu` |
| Rollout stalls | `maxUnavailable: 0` + not enough node capacity or failing readiness | `kubectl describe pod`; scale nodes |
