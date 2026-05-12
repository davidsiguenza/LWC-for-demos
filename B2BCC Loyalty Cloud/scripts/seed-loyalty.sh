#!/usr/bin/env bash
set -euo pipefail

# Seeds a minimal LoyaltyProgram into the target org from data/sample-loyalty-program.json.
# Skip if the user already picked an existing program in Phase 0 / Q3.
# Usage: ./scripts/seed-loyalty.sh <org-alias>

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <org-alias>" >&2
  exit 1
fi

ORG_ALIAS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
DATA_FILE="${PROJECT_ROOT}/data/sample-loyalty-program.json"

echo "→ Importing ${DATA_FILE} into org alias '${ORG_ALIAS}'…"
sf data tree import \
  --plan-or-file "${DATA_FILE}" \
  --target-org "${ORG_ALIAS}"

echo "✓ Seed complete. Remember to add LoyaltyTierGroup/Tiers and LoyaltyProgramCurrency manually (see data/README.md)."
