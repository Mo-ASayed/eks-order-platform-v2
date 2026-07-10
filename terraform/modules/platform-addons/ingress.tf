resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = local.traefik_namespace
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = local.cert_manager_namespace
  }
}

resource "kubernetes_namespace_v1" "external_dns" {
  metadata {
    name = local.external_dns_namespace
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_trust.json
}

resource "aws_iam_policy" "external_dns" {
  name   = "${var.cluster_name}-external-dns"
  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

resource "helm_release" "traefik" {
  name       = "traefik"
  namespace  = kubernetes_namespace_v1.traefik.metadata[0].name
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  wait       = true
  timeout    = 300

  values = [
    yamlencode({
      deployment = {
        replicas = 2
      }

      ingressClass = {
        enabled        = true
        isDefaultClass = true
        name           = "traefik"
      }

      providers = {
        kubernetesIngress = {
          enabled      = true
          ingressClass = "traefik"
          publishedService = {
            enabled = true
          }
        }
      }

      ports = {
        web = {
          http = {
            redirections = {
              entryPoint = {
                to        = "websecure"
                scheme    = "https"
                permanent = true
              }
            }
          }
        }
      }

      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"       = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"     = "internet-facing"
          "service.beta.kubernetes.io/aws-load-balancer-attributes" = "load_balancing.cross_zone.enabled=true"
        }
      }

      metrics = {
        prometheus = {
          serviceMonitor = {
            enabled = false
          }
        }
      }
    })
  ]
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  wait       = true
  timeout    = 300

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]
}

resource "kubectl_manifest" "letsencrypt_cluster_issuer" {
  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: ${local.letsencrypt_cluster_issuer}
    spec:
      acme:
        email: ${var.letsencrypt_email}
        server: https://acme-v02.api.letsencrypt.org/directory
        privateKeySecretRef:
          name: ${local.letsencrypt_cluster_issuer}
        solvers:
          - http01:
              ingress:
                class: traefik
  YAML

  depends_on = [
    helm_release.cert_manager,
    helm_release.traefik,
  ]
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = kubernetes_namespace_v1.external_dns.metadata[0].name
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  wait       = true
  timeout    = 300

  values = [
    yamlencode({
      provider = {
        name = "aws"
      }

      sources = [
        "ingress",
        "service",
      ]

      domainFilters = [
        var.domain_name,
      ]

      policy     = "upsert-only"
      registry   = "txt"
      txtOwnerId = var.cluster_name

      extraArgs = [
        "--aws-zone-type=public",
        "--zone-id-filter=${var.route53_zone_id}",
      ]

      serviceAccount = {
        create = true
        name   = local.external_dns_service_account
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
        }
      }
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.external_dns,
    helm_release.traefik,
  ]
}
