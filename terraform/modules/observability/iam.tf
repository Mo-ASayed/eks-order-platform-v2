data "aws_iam_policy_document" "yace_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:sub"
      values   = ["system:serviceaccount:${local.monitoring_namespace}:${local.yace_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "yace" {
  name               = "${var.cluster_name}-yace"
  assume_role_policy = data.aws_iam_policy_document.yace_trust.json
}

# Scoped to the AWS/SQS namespace only -- YACE never needs to read metrics
# outside the queues it's configured to scrape.
resource "aws_iam_role_policy" "yace" {
  name = "${var.cluster_name}-yace"
  role = aws_iam_role.yace.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "AWS/SQS"
          }
        }
      },
    ]
  })
}
