resource "aws_iam_role" "producer_role" {
  name               = "${var.cluster_name}-sqs-producer"
  assume_role_policy = data.aws_iam_policy_document.producer_trust.json
}

resource "aws_iam_role_policy" "producer_policy" {
  name = "${var.cluster_name}-sqs-producer"
  role = aws_iam_role.producer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.sqs_queue.arn
      },
    ]
  })
}


resource "aws_iam_role" "consumer_role" {
  name               = "${var.cluster_name}-sqs-consumer"
  assume_role_policy = data.aws_iam_policy_document.consumer_trust.json
}

resource "aws_iam_role_policy" "consumer_policy" {
  name = "${var.cluster_name}-sqs-consumer"
  role = aws_iam_role.consumer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ChangeMessageVisibility",
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.sqs_queue.arn
      },
    ]
  })
}
