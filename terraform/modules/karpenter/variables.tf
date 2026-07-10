# ---------------------------------------------------------------------------
# Inputs are wired from envs/dev using EKS and VPC outputs. This module consumes
# existing cluster, OIDC and node-role resources rather than creating them.
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name. Karpenter uses it for the discovery tag value, the Helm settings.clusterName, and the interruption queue name."
  type        = string
}

variable "cluster_endpoint" {
  description = "API server endpoint. Goes into Helm settings.clusterEndpoint."
  type        = string
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN from the eks module. The controller IRSA role trusts this."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL from the eks module. Used in the IRSA trust policy condition (sub = system:serviceaccount:<ns>:karpenter)."
  type        = string
}

variable "node_role_name" {
  description = "Existing node IAM role name from the eks module. Karpenter reuses it for the nodes it launches (EC2NodeClass spec.role) and it needs an EKS access entry so those nodes can join."
  type        = string
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version to install."
  type        = string
  default     = "1.13.0"
}

variable "karpenter_namespace" {
  description = "Kubernetes namespace to install Karpenter into."
  type        = string
  default     = "kube-system"
}
