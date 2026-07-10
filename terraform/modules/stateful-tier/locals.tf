locals {
  cnpg_namespace = "cnpg-system"
  data_namespace = "data"

  postgres_secret_name    = "${var.cluster_name}/secret/postgres/app"
  redis_secret_name       = "${var.cluster_name}/secret/redis"
  api_gateway_secret_name = "${var.cluster_name}/secret/api-gateway-secrets"
}
