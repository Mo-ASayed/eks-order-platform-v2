#!/usr/bin/env bash
# Delete CloudNativePG Clusters (and the redis StatefulSet) before Terraform
# removes the CNPG operator and the "data" namespace. The CNPG Cluster carries a
# cnpg.io finalizer that only the operator can clear; if Terraform uninstalls the
# operator helm release first (it races the namespace teardown), the Cluster is
# orphaned and the namespace hangs in Terminating until "context deadline
# exceeded". So we delete the Cluster with the operator still live, then strip
# stuck finalizers only as a destroy fallback.
#
# Namespaces mirror terraform/modules/stateful-tier/locals.tf.
# Requires AWS_REGION and must run from terraform/envs/dev.
set -euo pipefail

data_namespace="data"

cluster="$(terraform output -raw cluster_name 2>/dev/null || true)"
if [[ -z "$cluster" ]]; then
  echo "No cluster_name in state; skipping stateful-tier pre-clean."
  exit 0
fi

if ! aws eks describe-cluster --name "$cluster" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "Cluster $cluster no longer exists; skipping stateful-tier pre-clean."
  exit 0
fi

aws eks update-kubeconfig --name "$cluster" --region "${AWS_REGION}"

# Delete every CNPG Cluster in the data namespace with the operator still live,
# then strip the finalizer if deletion stalls so namespace teardown can finish.
if kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1; then
  for cl in $(kubectl -n "$data_namespace" get clusters.postgresql.cnpg.io -o name 2>/dev/null || true); do
    echo "Deleting CNPG $cl in namespace $data_namespace"
    if kubectl -n "$data_namespace" delete "$cl" --wait=true --timeout=5m; then
      continue
    fi

    echo "$cl did not delete cleanly; removing finalizers for teardown."
    kubectl -n "$data_namespace" get "$cl" -o yaml || true
    kubectl -n "$data_namespace" patch "$cl" \
      --type merge \
      -p '{"metadata":{"finalizers":[]}}' || true
    kubectl -n "$data_namespace" delete "$cl" --ignore-not-found --wait=false || true
  done
else
  echo "CNPG Cluster CRD is absent; skipping CNPG pre-clean."
fi

# Best-effort: drain the redis StatefulSet so its pod and PVC release before the
# namespace terminates. PVCs use gp3-retain, so the EBS volume is retained either
# way; this just avoids the namespace lingering on a slow pod shutdown.
if kubectl -n "$data_namespace" get statefulset redis >/dev/null 2>&1; then
  echo "Deleting redis StatefulSet in namespace $data_namespace"
  kubectl -n "$data_namespace" delete statefulset redis --wait=true --timeout=2m || true
fi

echo "Stateful-tier pre-clean complete."
