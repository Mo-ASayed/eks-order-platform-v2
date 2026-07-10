data "aws_iam_policy_document" "consumer_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringLike"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:sub"
      values   = ["system:serviceaccount:${var.workload_namespace_pattern}:${var.consumer_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "producer_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringLike"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:sub"
      values = [
        for service_account in var.producer_service_accounts :
        "system:serviceaccount:${var.workload_namespace_pattern}:${service_account}"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

