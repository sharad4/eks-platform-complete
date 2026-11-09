# ADR-0008: Prometheus, Grafana, Loki, Alloy and Tempo, self-hosted

- **Status:** Accepted
- **Deciders:** Platform owner

## Context
Metrics, logs and traces with one place to look, at a price a small team can carry.

## Decision
kube-prometheus-stack for metrics, alerts and Grafana; Loki (single binary, EBS) for logs shipped by Grafana Alloy; Tempo for traces. Everything, including dashboards, alert rules and SLO burn-rate alerts, is code in Git.

## Consequences
One UI with correlated metrics, logs and traces; Loki indexes labels only, so logs are far cheaper than Elasticsearch. Costs: you operate it (storage, upgrades, retention), Prometheus is a single replica with local disk (no HA, no long-term retention), and Loki on EBS will not scale far. Production-grade next steps are S3-backed Loki/Tempo and Mimir or Thanos, or Amazon Managed Prometheus/Grafana.

## Alternatives considered
Managed services (AMP/AMG/CloudWatch: less toil, more per-GB cost and lock-in); ELK (powerful full-text search, heavy to run); Datadog (excellent product, per-host pricing).
