output "argocd_port_forward" {
  value = module.addons.argocd_port_forward
}

output "argocd_admin_password_command" {
  value = module.addons.argocd_admin_password_command
}

output "external_secrets_role_arn" {
  value = module.addons.external_secrets_role_arn
}
