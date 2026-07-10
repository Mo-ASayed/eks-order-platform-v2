
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = local.github_oidc_url

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    data.tls_certificate.github_actions.certificates[0].sha1_fingerprint,
  ]


  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "github_actions_ecr" {
  name               = "${var.cluster_name}-github-actions-ecr"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  # Keep the CI identity in place so pipelines can rebuild after teardown.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  name   = "${var.cluster_name}-github-actions-ecr"
  role   = aws_iam_role.github_actions_ecr.id
  policy = data.aws_iam_policy_document.github_actions_ecr.json
}
