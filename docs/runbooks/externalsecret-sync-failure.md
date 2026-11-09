# Runbook: ExternalSecret not syncing

## Symptoms
Alert: `ExternalSecretSyncFailing`. Pods may fail with `CreateContainerConfigError` after a secret change.

## Triage
1. `kubectl get externalsecret -A` then `kubectl describe externalsecret <name> -n <ns>`; read the status message.
2. `kubectl get clustersecretstore aws-secrets-manager -o yaml`: is `status.conditions` Ready?
3. ESO logs: `kubectl -n external-secrets logs deploy/external-secrets --tail=100`.
4. Typical causes:
   - `AccessDeniedException`: the ESO IRSA policy does not list that secret ARN (`terraform output eso_read_policy_json` in the environment stack; re-apply the **addons** layer after changing it) or lacks `kms:Decrypt` for the RDS-managed secret's key.
   - `ResourceNotFoundException`: wrong key name; names are case-sensitive (`nonprod/dev/backend`).
   - `could not get provider client` / token errors: the ESO ServiceAccount lacks the `eks.amazonaws.com/role-arn` annotation, or the role trust policy namespace/serviceaccount does not match (`external-secrets:external-secrets`).
   - Secret deleted: Secrets Manager keeps it for the recovery window; `aws secretsmanager restore-secret --secret-id <name>`.

## Mitigation
Fix the IAM policy or key name, then force a resync: `kubectl annotate externalsecret <name> -n <ns> force-sync=$(date +%s) --overwrite`.

## Verify
ExternalSecret shows `SecretSynced`; the target Secret exists; restart pods that need new values: `kubectl -n <ns> rollout restart deploy/<name>`.

## Follow-up
Consider Stakater Reloader so pods restart automatically when a secret changes.
