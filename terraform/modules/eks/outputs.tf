output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint. Used to build kubeconfig."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA cert for the API server. Used to build kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Cluster security group EKS created. Other phases attach rules to it."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider. Every IRSA role trusts this."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL. Used in IRSA trust policy conditions."
  value       = aws_iam_openid_connect_provider.this.url
}

output "node_role_arn" {
  description = "Node IAM role ARN. Karpenter reuses this for the nodes it launches."
  value       = aws_iam_role.node_role.arn
}

output "node_role_name" {
  description = "Node IAM role name. Karpenter's access entry / instance profile needs it."
  value       = aws_iam_role.node_role.name
}
