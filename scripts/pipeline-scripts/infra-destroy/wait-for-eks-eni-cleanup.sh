#!/usr/bin/env bash
# Wait for EKS control-plane cross-account ENIs to clear from the VPC before
# Terraform destroys the subnets. The EKS service creates these ENIs itself
# (not tracked in Terraform state) and releases them asynchronously after
# DeleteCluster returns, so destroying module.eks and module.vpc back-to-back
# can race this cleanup and fail with DependencyViolation.
# Requires AWS_REGION and VPC_ID, and must run after module.eks is destroyed
# but before module.vpc is destroyed.
set -euo pipefail

vpc="${VPC_ID:?VPC_ID must be set}"

eks_enis_in_vpc() {
  aws ec2 describe-network-interfaces --region "${AWS_REGION}" \
    --filters "Name=vpc-id,Values=${vpc}" "Name=description,Values=Amazon EKS*" \
    --query "NetworkInterfaces[].NetworkInterfaceId" --output text 2>/dev/null || true
}

for _ in $(seq 1 30); do
  enis="$(eks_enis_in_vpc)"
  [[ -z "$enis" ]] && { echo "No EKS control-plane ENIs remain in VPC $vpc."; exit 0; }
  echo "Waiting for EKS control-plane ENIs to clear from VPC $vpc: $enis"
  sleep 10
done

echo "EKS control-plane ENIs still exist after wait; continuing so Terraform can report the exact blocker."
eks_enis_in_vpc
