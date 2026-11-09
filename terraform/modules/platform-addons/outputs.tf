output "alb_controller_role_arn" {
  value = module.alb_irsa.role_arn
}

output "external_secrets_role_arn" {
  description = "Role the ClusterSecretStore authenticates with (via the controller's ServiceAccount)."
  value       = module.eso_irsa.role_arn
}

output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "argocd_port_forward" {
  description = "Open the ArgoCD UI at http://localhost:8080"
  value       = "kubectl -n argocd port-forward svc/argocd-server 8080:80"
}

output "argocd_admin_password_command" {
  description = "Initial admin password (delete the secret after changing it)."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
