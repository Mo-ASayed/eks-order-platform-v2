variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN from the eks module. The controller IRSA role trusts this."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL from the eks module. Used in the IRSA trust policy condition (sub = system:serviceaccount:<ns>:karpenter)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name. Karpenter uses it for the discovery tag value, the Helm settings.clusterName, and the interruption queue name."
  type        = string
}

variable "domain_name" {
  description = "Public Route53 hosted zone name used for application ingress records."
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID ExternalDNS is allowed to manage."
  type        = string
}

variable "letsencrypt_email" {
  description = "Email address registered with Let's Encrypt for ACME certificate notices."
  type        = string
}
