module "vpc" {
  source = "../../modules/vpc"

  name               = var.cluster_name
  cluster_name       = var.cluster_name
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)

  single_nat_gateway = true # Cost-led dev default; set false for one NAT per AZ.
}

module "dns" {
  source = "../../modules/dns"

  domain_name = var.domain_name
}

module "eks" {
  source = "../../modules/eks"

  cluster_name           = var.cluster_name
  private_subnet_ids     = module.vpc.private_subnet_ids
  endpoint_public_access = true

  # Targeted EKS applies must also build NAT/routes. Without egress, private
  # nodes cannot reach ECR or the EKS endpoint and fail to join.
  depends_on = [module.vpc]
}

module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  node_role_name    = module.eks.node_role_name

  # Terraform needs cluster access before Helm or Kubernetes providers run.
  depends_on = [
    module.eks,
    time_sleep.wait_for_github_actions_access,
  ]
}

module "platform_addons" {
  source = "../../modules/platform-addons"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  domain_name       = var.domain_name
  route53_zone_id   = module.dns.zone_id
  letsencrypt_email = var.letsencrypt_email

  # Terraform needs cluster access before Kubernetes providers run.
  depends_on = [
    module.eks,
    time_sleep.wait_for_github_actions_access,
  ]
}

module "stateful_tier" {
  source = "../../modules/stateful-tier"

  cluster_name = module.eks.cluster_name

  depends_on = [
    module.platform_addons,
  ]
}

module "eventbus" {
  source = "../../modules/eventbus"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  depends_on = [
    module.platform_addons,
  ]
}

module "observability" {
  source = "../../modules/observability"

  cluster_name               = module.eks.cluster_name
  aws_region                 = var.region
  oidc_provider_arn          = module.eks.oidc_provider_arn
  oidc_provider_url          = module.eks.oidc_provider_url
  domain_name                = var.domain_name
  letsencrypt_cluster_issuer = module.platform_addons.cert_manager_cluster_issuer
  sqs_queue_name             = module.eventbus.sqs_queue_name
  sqs_deadletter_queue_name  = module.eventbus.sqs_deadletter_queue_name

  # platform_addons: Grafana ingress needs Traefik/cert-manager/ExternalDNS running.
  # stateful_tier:   the CNPG PodMonitor targets the "data" namespace this module creates.
  # eventbus:        YACE's scrape config is templated from the SQS queue names above.
  depends_on = [
    module.platform_addons,
    module.stateful_tier,
    module.eventbus,
  ]
}

module "github_actions" {
  source = "../../modules/github-actions"

  cluster_name      = var.cluster_name
  github_repository = var.github_repository

  ecr_repository_names = [
    "api-gateway-service",
    "dashboard-api",
    "inventory-service",
    "notification-service",
    "order-service",
    "payment-service",
    "scheduler",
    "shipping-service",
    "worker-service",
  ]
}
