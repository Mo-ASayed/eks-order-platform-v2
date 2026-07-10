#!/usr/bin/env bash
# Delete ArgoCD Applications before Terraform removes ArgoCD itself. This gives
# finalizers a live controller to prune with, then strips stuck finalizers only
# as a destroy fallback.
# Requires AWS_REGION and must run from terraform/envs/dev.
set -euo pipefail

cluster="$(terraform output -raw cluster_name 2>/dev/null || true)"
if [[ -z "$cluster" ]]; then
  echo "No cluster_name in state; skipping ArgoCD pre-clean."
  exit 0
fi

if ! aws eks describe-cluster --name "$cluster" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "Cluster $cluster no longer exists; skipping ArgoCD pre-clean."
  exit 0
fi

aws eks update-kubeconfig --name "$cluster" --region "${AWS_REGION}"

if ! kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  echo "ArgoCD Application CRD is absent; skipping ArgoCD pre-clean."
  exit 0
fi

delete_app() {
  local app="$1"
  if ! kubectl -n argocd get application.argoproj.io "$app" >/dev/null 2>&1; then
    return 0
  fi

  echo "Deleting ArgoCD application: $app"
  if kubectl -n argocd delete application.argoproj.io "$app" --wait=true --timeout=5m; then
    return 0
  fi

  echo "Application $app did not delete cleanly; removing finalizers for teardown."
  kubectl -n argocd get application.argoproj.io "$app" -o yaml || true
  kubectl -n argocd patch application.argoproj.io "$app" \
    --type merge \
    -p '{"metadata":{"finalizers":[]}}' || true
  kubectl -n argocd delete application.argoproj.io "$app" --ignore-not-found --wait=false || true
}

# Delete root first so selfHeal cannot recreate the leaf apps mid-teardown.
delete_app order-platform-root
delete_app order-platform-dev
delete_app order-platform-prod
