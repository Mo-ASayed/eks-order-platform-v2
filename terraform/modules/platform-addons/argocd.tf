resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = local.argocd_namespace

    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.5.22"

  values = [
    yamlencode({
      global = {
        domain = "argocd.${var.domain_name}"
      }
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      server = {
        ingress = {
          enabled          = true
          ingressClassName = "traefik"
          annotations = {
            "cert-manager.io/cluster-issuer"                   = local.letsencrypt_cluster_issuer
            "external-dns.alpha.kubernetes.io/hostname"        = "argocd.${var.domain_name}"
            "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
            "traefik.ingress.kubernetes.io/router.tls"         = "true"
          }
          hosts = [
            "argocd.${var.domain_name}",
          ]
          tls = [
            {
              secretName = "argocd-${replace(var.domain_name, ".", "-")}-tls"
              hosts = [
                "argocd.${var.domain_name}",
              ]
            }
          ]
        }
      }
    })
  ]

  depends_on = [
    helm_release.traefik,
    helm_release.cert_manager,
    helm_release.external_dns,
  ]
}

resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = file("${path.module}/../../../argocd/bootstrap/root.yaml")

  depends_on = [
    helm_release.argocd,
  ]
}
