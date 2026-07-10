variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "cluster_name" {
  description = "EKS cluster name. Must match between VPC subnet tags and the EKS module."
  type        = string
  default     = "eks-v2"
}

variable "domain_name" {
  description = "Public Route53 hosted zone name used for ExternalDNS/cert-manager later."
  type        = string
  default     = "lab.mohammedsayed.com"
}

variable "letsencrypt_email" {
  description = "Email address registered with Let's Encrypt for ACME certificate notices."
  type        = string
  default     = "sayedsylvainltd@gmail.com"
}

variable "github_repository" {
  description = "GitHub repository allowed to push application images through Actions OIDC. Also the GitOps repo ArgoCD reconciles."
  type        = string
  default     = "Mo-ASayed/eks-order-platform-v2"
}
