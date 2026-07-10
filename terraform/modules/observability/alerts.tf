# name="sqs-dlq" must match the YACE static job name in yace.tf; the Postgres
# and api-gateway selectors assume stateful-tier's "data" namespace/"postgres"
# Cluster name and the dev kustomize overlay's "apps-dev" namespace, same
# coupling as podmonitor.tf.
#
# SQSDeadLetterQueueNotEmpty duplicates eventbus's pre-existing CloudWatch
# alarm (aws_cloudwatch_metric_alarm.dlq_messages_visible) deliberately --
# that one pages outside Kubernetes; this one needs to fire inside
# Prometheus/Alertmanager per this phase's verify gate.
resource "kubectl_manifest" "platform_alerts" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: eks-v2-platform-alerts
      namespace: ${local.monitoring_namespace}
    spec:
      groups:
        - name: eks-v2.platform
          rules:
            - alert: SQSDeadLetterQueueNotEmpty
              expr: aws_sqs_approximate_number_of_messages_visible_maximum{name="sqs-dlq"} > 0
              for: 1m
              labels:
                severity: critical
              annotations:
                summary: "Messages are stuck in the SQS dead-letter queue"
                description: "{{ $value }} message(s) visible in the dead-letter queue for over 1 minute. A worker is failing to process events."
            - alert: PostgresInstanceDown
              expr: (up{namespace="data", pod=~"postgres-.*"} == 0) or (absent(up{namespace="data", pod=~"postgres-.*"}))
              for: 1m
              labels:
                severity: critical
              annotations:
                summary: "Postgres instance is unreachable"
                description: "Prometheus has not been able to scrape the Postgres pod {{ $labels.pod }} in namespace data for over 1 minute."
            - alert: APIGatewayReadinessFailing
              expr: kube_pod_status_ready{namespace="apps-dev", pod=~"api-gateway-.*", condition="true"} == 0
              for: 1m
              labels:
                severity: critical
              annotations:
                summary: "api-gateway pod is not ready"
                description: "Pod {{ $labels.pod }} in namespace apps-dev has failed its readiness probe for over 1 minute."
  YAML

  depends_on = [
    helm_release.kube_prometheus_stack,
  ]
}
