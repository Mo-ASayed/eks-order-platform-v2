#!/usr/bin/env bash
# Clean up Karpenter capacity before Terraform removes the cluster and VPC.
# Terraform does not track those EC2 instances, so freeze provisioning, delete
# NodeClaims best-effort, terminate backing instances and wait for ENIs.
# Requires AWS_REGION and must run from terraform/envs/dev.
set -euo pipefail

cluster="$(terraform output -raw cluster_name 2>/dev/null || true)"
if [[ -z "$cluster" ]]; then
  echo "No cluster_name in state; nothing to drain."
  exit 0
fi

if ! aws eks describe-cluster --name "$cluster" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "Cluster $cluster no longer exists; nothing to drain."
  exit 0
fi

aws eks update-kubeconfig --name "$cluster" --region "${AWS_REGION}"

vpc="$(aws eks describe-cluster --name "$cluster" --region "${AWS_REGION}" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)"

# Scope by Karpenter tag and VPC so this cannot touch another cluster.
# active: pending/running instances to terminate.
# alive: anything not fully terminated yet.
karpenter_active() {
  aws ec2 describe-instances --region "${AWS_REGION}" \
    --filters "Name=tag-key,Values=karpenter.sh/nodepool" \
              "Name=vpc-id,Values=${vpc}" \
              "Name=instance-state-name,Values=pending,running" \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true
}
karpenter_alive() {
  aws ec2 describe-instances --region "${AWS_REGION}" \
    --filters "Name=tag-key,Values=karpenter.sh/nodepool" \
              "Name=vpc-id,Values=${vpc}" \
              "Name=instance-state-name,Values=pending,running,stopping,shutting-down" \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true
}

# Freeze provisioning before deleting NodeClaims.
if kubectl get nodepools.karpenter.sh >/dev/null 2>&1; then
  for np in $(kubectl get nodepools.karpenter.sh -o name); do
    kubectl patch "$np" --type merge -p '{"spec":{"limits":{"cpu":"0"}}}' || true
  done
else
  echo "No NodePool CRD present; skipping provisioning freeze."
fi

# Delete NodeClaims without waiting; frozen capacity can leave PDBs blocking.
if kubectl get nodeclaims.karpenter.sh >/dev/null 2>&1; then
  kubectl delete nodeclaims.karpenter.sh --all --ignore-not-found --wait=false || true
else
  echo "No NodeClaim CRD / nodeclaims present; skipping."
fi

# Terminate backing instances directly and re-check for mid-launch nodes.
empty_streak=0
for _ in $(seq 1 12); do
  ids="$(karpenter_active)"
  if [[ -z "$ids" ]]; then
    empty_streak=$((empty_streak + 1))
    [[ "$empty_streak" -ge 2 ]] && { echo "No active Karpenter instances remain."; break; }
    sleep 10
    continue
  fi
  empty_streak=0
  echo "Terminating Karpenter instances: $ids"
  aws ec2 terminate-instances --region "${AWS_REGION}" --instance-ids $ids >/dev/null || true
  sleep 10
done

# Wait for ENIs to release before VPC destroy.
ids="$(karpenter_alive)"
if [[ -n "$ids" ]]; then
  echo "Waiting for Karpenter instances to finish terminating: $ids"
  aws ec2 wait instance-terminated --region "${AWS_REGION}" --instance-ids $ids || true
fi
echo "Karpenter drain complete."
