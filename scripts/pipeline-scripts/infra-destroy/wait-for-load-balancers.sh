#!/usr/bin/env bash
# Wait for Kubernetes-managed NLBs to disappear before VPC teardown, otherwise
# Terraform can race ENI cleanup.
# Requires AWS_REGION and must run from terraform/envs/dev.
set -euo pipefail

cluster="$(terraform output -raw cluster_name 2>/dev/null || true)"
if [[ -z "$cluster" ]]; then
  echo "No cluster_name in state; skipping load balancer wait."
  exit 0
fi

if ! aws eks describe-cluster --name "$cluster" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "Cluster $cluster no longer exists; skipping load balancer wait."
  exit 0
fi

vpc="$(aws eks describe-cluster --name "$cluster" --region "${AWS_REGION}" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)"

load_balancers_in_vpc() {
  aws elbv2 describe-load-balancers --region "${AWS_REGION}" \
    --query "LoadBalancers[?VpcId=='${vpc}'].LoadBalancerArn" \
    --output text 2>/dev/null || true
}

for _ in $(seq 1 30); do
  lbs="$(load_balancers_in_vpc)"
  [[ -z "$lbs" ]] && { echo "No load balancers remain in VPC $vpc."; exit 0; }
  echo "Waiting for load balancers in VPC $vpc to delete: $lbs"
  sleep 20
done

echo "Load balancers still exist after wait; continuing so Terraform can report the exact blocker."
load_balancers_in_vpc
