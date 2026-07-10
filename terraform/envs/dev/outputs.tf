# Export the values used by pipelines, scripts and downstream checks.
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "availability_zones" {
  value = module.vpc.availability_zones
}

output "route53_zone_id" {
  value = module.dns.zone_id
}

output "route53_name_servers" {
  value = module.dns.name_servers
}

output "stateful_namespace" {
  value = module.stateful_tier.namespace
}

output "postgres_service" {
  value = module.stateful_tier.postgres_service
}

output "redis_service" {
  value = module.stateful_tier.redis_service
}

output "sqs_queue_url" {
  value = module.eventbus.sqs_queue_url
}

output "sqs_queue_arn" {
  value = module.eventbus.sqs_queue_arn
}

output "sqs_deadletter_queue_url" {
  value = module.eventbus.sqs_deadletter_queue_url
}

output "sqs_deadletter_queue_arn" {
  value = module.eventbus.sqs_deadletter_queue_arn
}

output "sqs_producer_role_arn" {
  value = module.eventbus.sqs_producer_role_arn
}

output "sqs_consumer_role_arn" {
  value = module.eventbus.sqs_consumer_role_arn
}

output "dlq_alarm_name" {
  value = module.eventbus.dlq_alarm_name
}

output "dlq_alarm_arn" {
  value = module.eventbus.dlq_alarm_arn
}

output "application_url" {
  value = module.platform_addons.application_url
}

output "traefik_namespace" {
  value = module.platform_addons.traefik_namespace
}

output "cert_manager_cluster_issuer" {
  value = module.platform_addons.cert_manager_cluster_issuer
}

output "argocd_namespace" {
  value = module.platform_addons.argocd_namespace
}

output "argocd_url" {
  value = module.platform_addons.argocd_url
}

output "github_actions_ecr_role_arn" {
  description = "Set this as the GitHub Actions repository variable AWS_GITHUB_ACTIONS_ROLE_ARN."
  value       = module.github_actions.github_actions_ecr_role_arn
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "grafana_url" {
  description = "Public HTTPS URL for the Grafana UI."
  value       = module.observability.grafana_url
}
