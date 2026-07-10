#!/usr/bin/env bash
# Create the ECR repository if it does not already exist.
#
# Inputs (env):
#   REPO - ECR repository name
set -euo pipefail

aws ecr describe-repositories \
  --repository-names "${REPO}" \
  >/dev/null 2>&1 || \
aws ecr create-repository \
  --repository-name "${REPO}" \
  >/dev/null
