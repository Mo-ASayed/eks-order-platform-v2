resource "aws_cloudwatch_metric_alarm" "dlq_messages_visible" {
  alarm_name          = "${var.cluster_name}-sqs-dlq-messages-visible"
  alarm_description   = "Messages are visible in the ${aws_sqs_queue.sqs_queue_deadletter.name} DLQ."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.dlq_alarm_actions
  ok_actions          = var.dlq_alarm_ok_actions

  dimensions = {
    QueueName = aws_sqs_queue.sqs_queue_deadletter.name
  }
}