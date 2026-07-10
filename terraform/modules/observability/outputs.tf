output "grafana_url" {
  description = "Public HTTPS URL for the Grafana UI."
  value       = "https://${local.grafana_hostname}"
}

output "monitoring_namespace" {
  description = "Namespace where the observability stack is installed."
  value       = local.monitoring_namespace
}
