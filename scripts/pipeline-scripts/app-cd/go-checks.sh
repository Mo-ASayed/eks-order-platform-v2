#!/usr/bin/env bash
# Lint and test every Go service.
#
# Each service under services/ is its own module, so gofmt, go vet and go test
# run per-module. Any unformatted file, vet finding or failing test fails the
# run. Modules are discovered from disk, so adding a service needs no change
# here. No cloud credentials are used.
#
# Usage: bash scripts/pipeline-scripts/app-cd/go-checks.sh
set -euo pipefail

# Resolve the repo root from this script's own location so it behaves the same
# locally and in CI, whatever the current working directory is.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$repo_root"

modules="$(find services -maxdepth 2 -name go.mod -print | sort)"
if [[ -z "$modules" ]]; then
  echo "No Go modules found under services/" >&2
  exit 1
fi

fail=0
for mod in $modules; do
  dir="$(dirname "$mod")"
  echo "::group::$dir"
  (
    cd "$dir"

    # gofmt reports files that are not canonically formatted; any output fails.
    unformatted="$(gofmt -l .)"
    if [[ -n "$unformatted" ]]; then
      echo "gofmt: needs formatting (run 'gofmt -w .'):"
      echo "$unformatted"
      exit 1
    fi
    echo "gofmt: ok"

    go vet ./...
    echo "vet: ok"

    go test ./...
  ) || fail=1
  echo "::endgroup::"
done

if [[ "$fail" -ne 0 ]]; then
  echo "Go checks failed." >&2
  exit 1
fi
echo "All Go checks passed."
