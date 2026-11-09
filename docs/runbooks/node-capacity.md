# Runbook: Nodes full, pods Pending, disks filling

## Symptoms
Symptoms: Pending pods, `Insufficient cpu/memory`, `PersistentVolumeFillingUp`, HPA cannot scale.

## Triage
1. `kubectl get pods -A --field-selector=status.phase=Pending` and `kubectl describe pod <pod>` (Events say why).
2. `kubectl top nodes` and `kubectl describe nodes | grep -A8 "Allocated resources"`.
3. Quotas: `kubectl describe resourcequota -n <env>`.
4. IP exhaustion: events mentioning `failed to assign an IP address`. Check subnet free IPs; prefix delegation is enabled, but a /19 can still fill.
5. Disks: `kubectl get pvc -A` and the PVC usage panel; Prometheus, Loki, Tempo and Grafana all use volumes.

## Mitigation
- Capacity: raise the node group max/desired in Terraform (preferred) or temporarily with `aws eks update-nodegroup-config --cluster-name <c> --nodegroup-name <ng> --scaling-config minSize=2,maxSize=8,desiredSize=4`. Remember `desired_size` is ignored by Terraform.
- Quota: raise it via PR in `security/quotas/`.
- Volume: edit the PVC size (`allowVolumeExpansion` is on) or reduce retention in the Prometheus/Loki values.

## Verify
No Pending pods; disk usage prediction no longer negative.

## Follow-up
Add Karpenter or Cluster Autoscaler so capacity follows demand automatically (ADR-0002).
