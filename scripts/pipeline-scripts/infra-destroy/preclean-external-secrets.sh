#!/usr/bin/env bash
# Uninstall the external-secrets helm release before Terraform destroys
# module.platform_addons. The chart annotates its CRDs with
# helm.sh/resource-policy: keep, so on uninstall Helm keeps those CRDs and emits
# an informational "kept due to resource policy" message. The
# terraform-provider-helm destroy path surfaces that message as an error
# ("Unable to uninstall Helm release external-secrets: uninstallation
# completed") and leaves the release in state, stalling the platform_addons
# destroy for the full helm timeout. The helm CLI treats kept CRDs as a clean
# exit, so we uninstall here and drop the resources from state before
# `terraform destroy` runs.
# Requires AWS_REGION and must run from terraform/envs/dev.
set -euo pipefail

namespace="external-secrets"
release="external-secrets"

cluster="$(terraform output -raw cluster_name 2>/dev/null || true)"
if [[ -z "$cluster" ]]; then
  echo "No cluster_name in state; skipping external-secrets pre-clean."
  exit 0
fi

if ! aws eks describe-cluster --name "$cluster" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "Cluster $cluster no longer exists; skipping external-secrets pre-clean."
  exit 0
fi

aws eks update-kubeconfig --name "$cluster" --region "${AWS_REGION}"

# Delete the ClusterSecretStore first so it does not outlive the webhook it
# relies on; --wait=false because the CRD goes away with the cluster regardless.
kubectl delete clustersecretstore aws-secrets-manager --ignore-not-found --wait=false || true

# Uninstall via the helm CLI (clean exit on kept CRDs) when it is available.
# If helm is missing we fall through to the state rm below; the release is then
# torn down with the cluster in the later module.eks destroy.
if command -v helm >/dev/null 2>&1; then
  if helm status -n "$namespace" "$release" >/dev/null 2>&1; then
    echo "Uninstalling helm release $release"
    helm uninstall -n "$namespace" "$release" --wait --timeout 5m || true
  else
    echo "Helm release $release not found; nothing to uninstall."
  fi
else
  echo "helm CLI not found; skipping uninstall, will rely on cluster teardown."
fi

# Drop the now-uninstalled resources from state so terraform destroy does not
# re-run its own (error-prone) uninstall.
terraform state rm 'module.platform_addons.kubectl_manifest.aws_secrets_manager_cluster_secret_store' 2>/dev/null || true
terraform state rm 'module.platform_addons.helm_release.external_secrets' 2>/dev/null || true

echo "external-secrets pre-clean complete."
