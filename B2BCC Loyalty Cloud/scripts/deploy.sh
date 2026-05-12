#!/usr/bin/env bash
set -euo pipefail

# Deploys the connector's SFDX source to the target org.
# Usage: ./scripts/deploy.sh <org-alias>

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <org-alias>" >&2
  exit 1
fi

ORG_ALIAS="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
SOURCE_DIR="${PROJECT_ROOT}/sfdx-source/force-app"

echo "→ Deploying ${SOURCE_DIR} to org alias '${ORG_ALIAS}'…"
sf project deploy start \
  --source-dir "${SOURCE_DIR}" \
  --target-org "${ORG_ALIAS}" \
  --wait 20

echo "✓ Deploy complete."
