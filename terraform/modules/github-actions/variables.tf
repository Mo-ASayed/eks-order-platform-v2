variable "cluster_name" {
  description = "Name prefix used for IAM resources."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the Actions role, in owner/name form."
  type        = string
}

variable "allowed_refs" {
  description = "Git refs in the repository that may assume the role."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "allowed_environments" {
  description = "GitHub Environments whose jobs may assume the role. Jobs that reference an environment get an environment-scoped OIDC subject instead of a ref-scoped one."
  type        = list(string)
  default     = ["dev"]
}

variable "ecr_repository_names" {
  description = "ECR repositories the GitHub Actions role may push to."
  type        = list(string)
}
