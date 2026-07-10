# The event-bus-ingress dashboard's api-gateway panels filter Traefik's
# "service" label by substring match (".*api-gateway.*"), since Traefik's
# Kubernetes-Ingress-provider names services "<service>-<namespace>-<port>
# @kubernetescrd" rather than the bare k8s Service name -- "api-gateway" is
# currently unique across the cluster's Services, so this is safe.
resource "kubernetes_config_map_v1" "dashboard_data_tier" {
  metadata {
    name      = "dashboard-data-tier"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "data-tier.json" = file("${path.module}/dashboards/data-tier.json")
  }
}

resource "kubernetes_config_map_v1" "dashboard_event_bus_ingress" {
  metadata {
    name      = "dashboard-event-bus-ingress"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "event-bus-ingress.json" = file("${path.module}/dashboards/event-bus-ingress.json")
  }
}
