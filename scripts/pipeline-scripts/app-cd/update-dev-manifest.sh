#!/usr/bin/env bash
# Pin each built service to its immutable image tag in the dev overlay and push
# the GitOps commit. Re-syncs with main between attempts so concurrent updates
# do not commit against a stale overlay.
#
# Run from the dev overlay directory (Kubernetes/apps/overlays/dev).
#
# Inputs (env):
#   MATRIX          - JSON array of built service names
#   TAG             - immutable image tag to pin
#   AWS_ACCOUNT_ID  - AWS account id
#   AWS_REGION      - AWS region
# Auto (GitHub):
#   GITHUB_REF_NAME
set -euo pipefail

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Pin each built service to the immutable tag in the dev overlay.
set_image_tags() {
  for service in $(jq -r '.[]' <<<"$MATRIX"); do
    case "$service" in
      api-gateway) repo="api-gateway-service" ;;
      worker)      repo="worker-service" ;;
      *)           repo="$service" ;;
    esac
    image="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}"
    kustomize edit set image "${image}=${image}:${TAG}"
  done
}

# Fetch main before each push so concurrent GitOps updates do not
# leave this run committing against a stale overlay.
for attempt in 1 2 3 4 5; do
  git fetch origin "${GITHUB_REF_NAME}"
  git reset --hard "origin/${GITHUB_REF_NAME}"

  set_image_tags

  if git diff --quiet -- kustomization.yaml; then
    echo "Overlay already up to date; nothing to commit."
    exit 0
  fi

  git add kustomization.yaml
  git commit -m "chore: deploy app images ${TAG}"

  if git push origin "HEAD:${GITHUB_REF_NAME}"; then
    echo "Pushed GitOps update on attempt ${attempt}."
    exit 0
  fi

  echo "Push rejected on attempt ${attempt}; main moved, re-syncing and retrying..."
  sleep $((RANDOM % 5 + 2))
done

echo "Failed to push GitOps update after 5 attempts." >&2
exit 1
