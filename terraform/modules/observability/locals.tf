locals {
  monitoring_namespace = "monitoring"
  yace_service_account = "yace"
  grafana_hostname     = "grafana.${var.domain_name}"
}
