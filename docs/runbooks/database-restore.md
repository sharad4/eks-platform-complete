# Runbook: RDS failure or data restore (point-in-time recovery)

## Symptoms
Symptoms: backend `/readyz` failing, `Multi-AZ failover` events, data corruption or an accidental destructive migration.

## Triage
1. **Failover** (instance/AZ failure on Multi-AZ prod) is automatic: the endpoint stays the same and flips in ~60-120 s. Confirm in **RDS -> Events**. Pods reconnect; no action beyond watching error rate.
2. **Corruption or bad migration:** decide the restore time **just before** the damage. Stop writes first: scale the worker and backend to 0 (or put the app in maintenance) so the bad state does not grow.
3. Restore to a NEW instance (never over the live one):
   ```
   aws rds restore-db-instance-to-point-in-time \
     --source-db-instance-identifier eks-platform-production \
     --target-db-instance-identifier eks-platform-production-restore \
     --restore-time 2026-01-31T09:55:00Z \
     --db-subnet-group-name eks-platform-production \
     --vpc-security-group-ids <rds-sg-id> --no-multi-az
   ```
4. Validate the restored data with a read-only query from a debug pod.

## Mitigation
Either repoint the app by changing the DB host in the Secrets Manager secret and letting ESO sync (then restart pods), or dump the lost rows from the restore and re-apply them to the live database. The second option avoids a long cutover when only a table is affected.

## Verify
`/readyz` is 200, error rate normal, row counts match expectations.

## Follow-up
Import the restored instance into Terraform (or recreate via code) so state matches reality. Practice this quarterly: an untested backup is not a backup (see `docs/disaster-recovery.md`).
