variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.36"
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from VPC module."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "endpoint_public_access" {
  description = "Whether the EKS cluster endpoint is publicly accessible. Set to false for private-only access, true for public access (default true for dev)."
  type        = bool
  default     = true
}

variable "admin_principal_arn" {
  description = "ARN of the IAM principal (user or role) that can authenticate to the cluster."
  type        = string

  default = "arn:aws:iam::767398132018:user/MohammedSayed"
}