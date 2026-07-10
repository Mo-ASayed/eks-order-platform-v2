variable "cluster_name" {
  description = "EKS cluster name, used to namespace IAM roles."
  type        = string
}

variable "aws_region" {
  description = "AWS region the cluster and SQS queues run in."
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

variable "domain_name" {
  description = "Public Route53 hosted zone name. Used for the Grafana ingress hostname."
  type        = string
}

variable "letsencrypt_cluster_issuer" {
  description = "cert-manager ClusterIssuer name to request the Grafana TLS cert from."
  type        = string
}

variable "sqs_queue_name" {
  description = "Name of the main SQS queue, scraped by YACE for dashboards."
  type        = string
}

variable "sqs_deadletter_queue_name" {
  description = "Name of the SQS dead-letter queue, scraped by YACE for the DLQ depth alert."
  type        = string
}
