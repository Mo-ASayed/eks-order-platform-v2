output "namespace" {
  description = "Namespace that contains the stateful workloads."
  value       = local.data_namespace
}

output "postgres_service" {
  description = "CloudNativePG read/write service for application database traffic."
  value       = "postgres-rw.${local.data_namespace}.svc.cluster.local"
}

output "redis_service" {
  description = "Redis service DNS name."
  value       = "redis.${local.data_namespace}.svc.cluster.local"
}

output "api_gateway_secret_name" {
  description = "AWS Secrets Manager secret name containing the API gateway JWT secret."
  value       = local.api_gateway_secret_name
}
