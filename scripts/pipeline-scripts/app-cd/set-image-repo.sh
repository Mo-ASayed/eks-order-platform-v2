#!/usr/bin/env bash
# Resolve the ECR repo name and full image URI for a service, emitting both to
# GITHUB_OUTPUT (repo, image).
#
# Inputs (env):
#   SERVICE         - service folder name (matrix.service)
#   AWS_ACCOUNT_ID  - AWS account id
#   AWS_REGION      - AWS region
# Auto (GitHub):
#   GITHUB_OUTPUT
set -euo pipefail

case "${SERVICE}" in
  api-gateway) repo="api-gateway-service" ;;
  worker)      repo="worker-service" ;;
  *)           repo="${SERVICE}" ;;
esac

image="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"
echo "repo=$repo" >> "$GITHUB_OUTPUT"
echo "image=$image" >> "$GITHUB_OUTPUT"
