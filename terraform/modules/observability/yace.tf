locals {
  yace_config = <<-YACE
    apiVersion: v1alpha1
    sts-region: ${var.aws_region}
    static:
      - namespace: AWS/SQS
        name: sqs-main
        regions:
          - ${var.aws_region}
        dimensions:
          - name: QueueName
            value: ${var.sqs_queue_name}
        metrics:
          - name: ApproximateNumberOfMessagesVisible
            statistics: [Maximum]
            period: 60
            length: 300
      - namespace: AWS/SQS
        name: sqs-dlq
        regions:
          - ${var.aws_region}
        dimensions:
          - name: QueueName
            value: ${var.sqs_deadletter_queue_name}
        metrics:
          - name: ApproximateNumberOfMessagesVisible
            statistics: [Maximum]
            period: 60
            length: 300
  YACE
}

resource "helm_release" "yace" {
  name       = "yace"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://nerdswords.github.io/helm-charts"
  chart      = "yet-another-cloudwatch-exporter"
  wait       = true
  timeout    = 300

  values = [
    yamlencode({
      config = local.yace_config

      serviceAccount = {
        create = true
        name   = local.yace_service_account
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.yace.arn
        }
      }

      serviceMonitor = {
        enabled = true
      }
    })
  ]

  depends_on = [
    aws_iam_role_policy.yace,
    helm_release.kube_prometheus_stack,
  ]
}
