#!/usr/bin/env bash
# Decide which services to build and emit matrix/count/tag to GITHUB_OUTPUT.
#
# A service is selected when its code changed in this push, or when its rendered
# dev image tag is missing from ECR (fresh accounts, emptied repos, manual ECR
# cleanup). "all" and an explicit service name short-circuit the detection.
#
# Inputs (env):
#   REQUESTED   - "changed" | "all" | a service name (workflow input)
#   BEFORE_SHA  - github.event.before (push) for the changed-files diff
#   ACCOUNT_ID  - AWS account id, for the ECR registry host
#   AWS_REGION  - AWS region, for the ECR registry host
# Auto (GitHub):
#   GITHUB_SHA, GITHUB_EVENT_NAME, GITHUB_OUTPUT
set -euo pipefail

tag="${GITHUB_SHA::7}"
requested="${REQUESTED:-changed}"

services=(
  api-gateway
  dashboard-api
  inventory-service
  notification-service
  order-service
  payment-service
  scheduler
  shipping-service
  worker
)

# Map ECR repo names back to service folders.
svc_for_repo() {
  case "$1" in
    api-gateway-service) echo "api-gateway" ;;
    worker-service)      echo "worker" ;;
    *)                   echo "$1" ;;
  esac
}

declare -A want=()

if [[ "$requested" == "all" ]]; then
  for s in "${services[@]}"; do want["$s"]=1; done
elif [[ "$requested" != "changed" ]]; then
  want["$requested"]=1
else
  # Build services changed in this push.
  if [[ "${GITHUB_EVENT_NAME}" == "workflow_dispatch" ]]; then
    changed_files="$(git diff --name-only HEAD~1 HEAD || true)"
  else
    changed_files="$(git diff --name-only "${BEFORE_SHA}" "${GITHUB_SHA}" || git diff --name-only HEAD~1 HEAD || true)"
  fi
  for s in "${services[@]}"; do
    if grep -qE "^services/${s}/" <<<"$changed_files"; then
      want["$s"]=1
      echo "Code changed -> will build $s"
    fi
  done

  # Also build services whose rendered dev image tag is missing in ECR.
  # This covers fresh accounts, emptied repos and manual ECR cleanup.
  registry="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  rendered="$(kustomize build Kubernetes/apps/overlays/dev)"
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    repo_tag="${ref#"$registry"/}"
    if [[ "$repo_tag" == *:* ]]; then
      repo="${repo_tag%%:*}"
      imgtag="${repo_tag##*:}"
    else
      repo="$repo_tag"
      imgtag="latest"
    fi
    if ! aws ecr describe-images \
           --repository-name "$repo" \
           --image-ids imageTag="$imgtag" >/dev/null 2>&1; then
      svc="$(svc_for_repo "$repo")"
      want["$svc"]=1
      echo "Image missing in ECR ($repo:$imgtag) -> will build $svc"
    fi
  done < <(grep -oE "${registry}/[A-Za-z0-9._:-]+" <<<"$rendered" | sort -u)
fi

if [[ ${#want[@]} -gt 0 ]]; then
  matrix="$(printf '%s\n' "${!want[@]}" | jq -Rsc 'split("\n") | map(select(length > 0)) | sort')"
else
  matrix='[]'
fi
count="$(jq 'length' <<<"$matrix")"

echo "matrix=$matrix" >> "$GITHUB_OUTPUT"
echo "count=$count" >> "$GITHUB_OUTPUT"
echo "tag=$tag" >> "$GITHUB_OUTPUT"
echo "Selected services: $matrix"
