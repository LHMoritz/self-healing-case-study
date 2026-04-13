#!/bin/bash
set -euo pipefail

# ============================================================================
# Secret Expiration Experiment — TRIGGER FAILURE
# ============================================================================
# This script simulates a secret misconfiguration by updating the Azure Key
# Vault secret to an invalid DB host value and restarting the persistence pod.
# The pod will start but fail to connect to the database.
#
# Prerequisites:
#   - Experiment activated via activate.sh
#
# Usage: ./trigger-failure.sh [namespace]
# ============================================================================

NAMESPACE="${1:-teastore}"
KEYVAULT_NAME="<YOUR_KEYVAULT_NAME>"
SECRET_NAME="teastore-db-host"
INVALID_VALUE="teastore-db-invalid"

echo "============================================"
echo " Secret Expiration — TRIGGER FAILURE"
echo " Namespace: ${NAMESPACE}"
echo "============================================"
echo ""

# --- Step 1: Update secret to invalid value ---
echo "▸ Setting '${SECRET_NAME}' to invalid value '${INVALID_VALUE}'..."
az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "${SECRET_NAME}" \
  --value "${INVALID_VALUE}" \
  --output none
echo "  ✓ Secret updated in Key Vault"

# --- Step 2: Restart the pod so CSI Driver re-fetches ---
echo ""
echo "▸ Restarting teastore-persistence to pick up new secret..."
kubectl rollout restart deployment teastore-persistence -n "${NAMESPACE}"

echo "▸ Waiting for rollout..."
kubectl rollout status deployment/teastore-persistence -n "${NAMESPACE}" --timeout=120s

# --- Step 3: Show result ---
echo ""
echo "▸ Current DB_HOST value in K8s Secret:"
DB_HOST=$(kubectl get secret teastore-db-secret -n "${NAMESPACE}" \
  -o jsonpath='{.data.db-host}' 2>/dev/null | base64 -d 2>/dev/null || echo "NOT_FOUND")
echo "  → ${DB_HOST}"

echo ""
echo "============================================"
echo " ✓ Failure TRIGGERED"
echo ""
echo " teastore-persistence is now using an"
echo " invalid DB_HOST. It will fail to connect"
echo " to the database."
echo ""
echo " Check pod logs:"
echo "   kubectl logs -l run=teastore-persistence"
echo "     -n ${NAMESPACE} --tail=20"
echo ""
echo " To restore, run: ./deactivate.sh"
echo "============================================"
