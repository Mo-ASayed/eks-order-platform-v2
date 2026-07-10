locals {
  ebs_csi_namespace                = "kube-system"
  ebs_csi_service_account          = "ebs-csi-controller-sa"
  external_secrets_namespace       = "external-secrets"
  external_secrets_service_account = "external-secrets"
  cert_manager_namespace           = "cert-manager"
  external_dns_namespace           = "external-dns"
  external_dns_service_account     = "external-dns"
  traefik_namespace                = "traefik"
  argocd_namespace                 = "argocd"
  application_hostname             = "app.${var.domain_name}"
  letsencrypt_cluster_issuer       = "letsencrypt-production"
}
