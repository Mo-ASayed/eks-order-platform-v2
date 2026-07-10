variable "cluster_name" {
  description = "EKS cluster name, used for namespacing event bus resources."
  type        = string
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN from the EKS module. IRSA roles trust this provider."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL from the EKS module. Used in IRSA trust policy conditions."
  type        = string
}

variable "workload_namespace_pattern" {
  description = "IAM StringLike glob matching the Kubernetes namespaces that run the SQS producer/consumer service accounts. The base manifests' \"apps\" namespace is never deployed as-is -- every kustomize overlay renames it (apps-dev, apps-prod, ...) -- so a wildcard covers all of them without listing each one."
  type        = string
  default     = "apps-*"
}

variable "producer_service_accounts" {
  description = "Kubernetes service account names allowed to send messages to the main queue."
  type        = list(string)
  default     = ["order-service", "payment-service", "shipping-service"]
}

variable "consumer_service_account" {
  description = "Kubernetes service account name allowed to consume messages from the main queue."
  type        = string
  default     = "worker"
}

variable "dlq_alarm_actions" {
  description = "CloudWatch alarm action ARNs to invoke when messages are visible in the DLQ. Leave empty until alerting is wired."
  type        = list(string)
  default     = []
}

variable "dlq_alarm_ok_actions" {
  description = "CloudWatch alarm action ARNs to invoke when the DLQ alarm returns to OK. Leave empty until alerting is wired."
  type        = list(string)
  default     = []
}
