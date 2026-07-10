data "aws_caller_identity" "current" {}

data "tls_certificate" "github_actions" {
  url = local.github_oidc_url
}



data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.github_oidc_host}:sub"
      values   = local.allowed_subjects
    }
  }
}

data "aws_iam_policy_document" "github_actions_ecr" {
  statement {
    sid = "EcrLogin"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid = "CreateAndReadRepositories"
    actions = [
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
    ]
    resources = ["*"]
  }

  statement {
    sid = "PushImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      for name in var.ecr_repository_names :
      "arn:aws:ecr:*:${data.aws_caller_identity.current.account_id}:repository/${name}"
    ]
  }
}
