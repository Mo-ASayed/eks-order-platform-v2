#!/usr/bin/env bash
# Guard the destroy job with an exact typed phrase. CONFIRM_PHRASE comes from
# env, not shell interpolation, so arbitrary input cannot alter the command.
set -euo pipefail

expected="${1:?usage: validate-confirmation.sh <expected-phrase>}"

if [[ "${CONFIRM_PHRASE:-}" != "$expected" ]]; then
  echo "Confirmation phrase did not match '${expected}'. Aborting." >&2
  exit 1
fi

echo "Confirmation phrase matched; proceeding with destroy."
