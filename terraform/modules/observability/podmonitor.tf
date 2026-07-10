# namespace/cnpg.io/cluster below must match stateful-tier's data_namespace
# ("data") and its CNPG Cluster name ("postgres") -- both are fixed literals
# there too, so this is not expected to drift.
resource "kubectl_manifest" "cnpg_postgres_podmonitor" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: PodMonitor
    metadata:
      name: cnpg-postgres
      namespace: data
    spec:
      selector:
        matchLabels:
          cnpg.io/cluster: postgres
      podMetricsEndpoints:
        - port: metrics
  YAML

  depends_on = [
    helm_release.kube_prometheus_stack,
  ]
}
