resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = local.monitoring_namespace
  }
}
