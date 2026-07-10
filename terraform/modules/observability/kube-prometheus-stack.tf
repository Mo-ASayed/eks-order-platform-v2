resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  wait       = true
  timeout    = 600

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention                               = "7d"
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false

          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3-ephemeral"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "20Gi"
                  }
                }
              }
            }
          }
        }
      }

      grafana = {
        defaultDashboardsEnabled = true

        persistence = {
          enabled = false
        }

        sidecar = {
          dashboards = {
            enabled         = true
            searchNamespace = "ALL"
          }
        }

        ingress = {
          enabled          = true
          ingressClassName = "traefik"
          annotations = {
            "cert-manager.io/cluster-issuer"                   = var.letsencrypt_cluster_issuer
            "external-dns.alpha.kubernetes.io/hostname"        = local.grafana_hostname
            "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
            "traefik.ingress.kubernetes.io/router.tls"         = "true"
          }
          hosts = [local.grafana_hostname]
          tls = [
            {
              secretName = "grafana-${replace(var.domain_name, ".", "-")}-tls"
              hosts = [
                local.grafana_hostname,
              ]
            }
          ]
        }
      }
    })
  ]
}
