data "aws_iam_policy_document" "ebs_csi_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:sub"
      values   = ["system:serviceaccount:${local.ebs_csi_namespace}:${local.ebs_csi_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "external_secrets_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:sub"
      values   = ["system:serviceaccount:${local.external_secrets_namespace}:${local.external_secrets_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}


data "aws_iam_policy_document" "external_secrets" {
  statement {
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:ListSecretVersionIds",
    ]

    resources = [
      "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}/secret/*",
    ]
  }
}

data "aws_iam_policy_document" "external_dns_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:sub"
      values   = ["system:serviceaccount:${local.external_dns_namespace}:${local.external_dns_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.oidc_provider_url, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "external_dns" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
    ]

    resources = [
      "arn:aws:route53:::hostedzone/${var.route53_zone_id}",
    ]
  }

  statement {
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "route53:GetChange",
    ]

    resources = [
      "arn:aws:route53:::change/*",
    ]
  }
}
