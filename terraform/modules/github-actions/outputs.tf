output "github_actions_ecr_role_arn" {
  description = "IAM role ARN to store as GitHub Actions variable AWS_GITHUB_ACTIONS_ROLE_ARN."
  value       = aws_iam_role.github_actions_ecr.arn
}

output "github_actions_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
