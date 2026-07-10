output "application_url" {
  description = "Public HTTPS URL served by Traefik once ExternalDNS has created the Route53 record."
  value       = "https://${local.application_hostname}"
}

output "traefik_namespace" {
  description = "Namespace where the Traefik ingress controller is installed."
  value       = local.traefik_namespace
}

output "cert_manager_cluster_issuer" {
  description = "ClusterIssuer name used by public application Ingress resources."
  value       = local.letsencrypt_cluster_issuer
}

output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed."
  value       = local.argocd_namespace
}

output "argocd_url" {
  description = "Public HTTPS URL for the ArgoCD API/UI."
  value       = "https://argocd.${var.domain_name}"
}
