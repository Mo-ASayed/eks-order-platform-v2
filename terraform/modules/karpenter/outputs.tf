output "controller_role_arn" {
  description = "Karpenter controller IRSA role ARN."
  value       = aws_iam_role.controller.arn
}

output "node_pool_name" {
  description = "Default NodePool name, handy for the verify gate."
  value       = "${var.cluster_name}-nodepool"
}

output "interruption_queue_name" {
  description = "SQS interruption queue name."
  value       = aws_sqs_queue.interruption.name
}

output "interruption_queue_arn" {
  description = "SQS interruption queue ARN."
  value       = aws_sqs_queue.interruption.arn
}