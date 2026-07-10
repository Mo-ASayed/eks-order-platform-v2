output "sqs_queue_url" {
  description = "URL of the SQS queue."
  value       = aws_sqs_queue.sqs_queue.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue."
  value       = aws_sqs_queue.sqs_queue.arn
}

output "sqs_deadletter_queue_url" {
  description = "URL of the SQS dead-letter queue."
  value       = aws_sqs_queue.sqs_queue_deadletter.url
}

output "sqs_deadletter_queue_arn" {
  description = "ARN of the SQS dead-letter queue."
  value       = aws_sqs_queue.sqs_queue_deadletter.arn
}

output "sqs_producer_role_arn" {
  description = "IRSA role ARN for SQS producer service accounts."
  value       = aws_iam_role.producer_role.arn
}

output "sqs_consumer_role_arn" {
  description = "IRSA role ARN for the SQS consumer service account."
  value       = aws_iam_role.consumer_role.arn
}

output "dlq_alarm_name" {
  description = "CloudWatch alarm name for messages visible in the SQS dead-letter queue."
  value       = aws_cloudwatch_metric_alarm.dlq_messages_visible.alarm_name
}

output "dlq_alarm_arn" {
  description = "CloudWatch alarm ARN for messages visible in the SQS dead-letter queue."
  value       = aws_cloudwatch_metric_alarm.dlq_messages_visible.arn
}

output "sqs_queue_name" {
  description = "Name of the main SQS queue."
  value       = aws_sqs_queue.sqs_queue.name
}

output "sqs_deadletter_queue_name" {
  description = "Name of the SQS dead-letter queue."
  value       = aws_sqs_queue.sqs_queue_deadletter.name
}
