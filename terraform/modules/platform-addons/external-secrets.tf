resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = local.external_secrets_namespace
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.cluster_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_trust.json
}

resource "aws_iam_policy" "external_secrets" {
  name   = "${var.cluster_name}-external-secrets"
  policy = data.aws_iam_policy_document.external_secrets.json
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  wait       = true
  timeout    = 300

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = local.external_secrets_service_account
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.external_secrets.arn
    }
  ]

  depends_on = [
    aws_iam_role_policy_attachment.external_secrets,
  ]
}

resource "kubectl_manifest" "aws_secrets_manager_cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1
    kind: ClusterSecretStore
    metadata:
      name: aws-secrets-manager
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${data.aws_region.current.name}
          auth:
            jwt:
              serviceAccountRef:
                name: ${local.external_secrets_service_account}
                namespace: ${local.external_secrets_namespace}
  YAML

  depends_on = [
    helm_release.external_secrets,
  ]
}
