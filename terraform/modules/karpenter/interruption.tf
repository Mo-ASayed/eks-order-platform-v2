# EventBridge sends interruption events to SQS. Karpenter polls the queue and
# drains affected nodes before AWS reclaims or retires them.
resource "aws_sqs_queue" "interruption" {
  name                    = "${var.cluster_name}-karpenter-interruption"
  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.interruption.arn
      },
    ]
  })
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_event_patterns

  name          = "${var.cluster_name}-karpenter-${each.key}"
  event_pattern = jsonencode(each.value)
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.interruption_event_patterns

  rule      = aws_cloudwatch_event_rule.interruption[each.key].name
  target_id = each.key
  arn       = aws_sqs_queue.interruption.arn
}
