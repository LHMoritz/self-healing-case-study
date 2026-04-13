#!/bin/bash
set -euo pipefail

# ============================================================================
# Persistent Volume Claim Storage Exhaustion — DEACTIVATE
# ============================================================================
# This script removes the PVC and the sidecar container, returning the
# teastore-db deployment to its original state (using ephemeral storage).
#
# Prerequisites:
#   - Experiment activated via activate.sh
# ============================================================================

NAMESPACE="${1:-teastore}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==================================================="
echo " PVC Storage Exhaustion — DEACTIVATE"
echo " Namespace: ${NAMESPACE}"
echo "==================================================="
echo ""

# 1. Revert teastore-db Deployment
echo "▸ Reverting teastore-db deployment to remove the PVC and sidecar..."
kubectl rollout undo deployment/teastore-db -n "${NAMESPACE}"

# 2. Delete the bloated PVC
echo ""
echo "▸ Deleting the saturated PVC..."
kubectl delete -f "${SCRIPT_DIR}/manifests/db-pvc.yaml" -n "${NAMESPACE}" --ignore-not-found

# 3. Wait for rollout
echo ""
echo "▸ Waiting for the restored teastore-db pod to start..."
kubectl rollout status deployment/teastore-db -n "${NAMESPACE}" --timeout=120s

# 4. Status
echo ""
echo "======================================================================"
echo " ✓ PVC Exhaustion Experiment Deactivated"
echo "======================================================================"
echo " The original MariaDB configuration is restored."
echo " Locust should return to normal response rates without 500 errors."
